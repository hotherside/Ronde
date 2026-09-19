#!/usr/bin/env python3
"""Synthetic EdgeTAM image/memory component Core ML probe.

The wrappers call the pinned model components directly. Inputs are explicit float32
normalised tensors, so Core ML ImageType preprocessing cannot silently change parity.
This probe uses no media, labels, coordinates, or tracking outputs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path
import sys
import time
import traceback

import coremltools as ct
import numpy as np
import torch
from hydra import compose, initialize_config_dir
from hydra.core.global_hydra import GlobalHydra
from hydra.utils import instantiate
from omegaconf import OmegaConf

REPOSITORY = Path(__file__).resolve().parents[4]
MEAN = (0.485, 0.456, 0.406)
STD = (0.229, 0.224, 0.225)


def external(path: Path, kind: str) -> Path:
    resolved = path.expanduser().resolve()
    if resolved == REPOSITORY or REPOSITORY in resolved.parents:
        raise ValueError(f"{kind} must be outside the repository")
    return resolved


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


class ImageEncoderWrapper(torch.nn.Module):
    """Exact raw ``forward_image`` path for already-normalised input."""

    def __init__(self, model: torch.nn.Module):
        super().__init__()
        self.model = model

    def forward(self, image_normalised: torch.Tensor):
        backbone = self.model.forward_image(image_normalised)
        fpn = backbone["backbone_fpn"]
        if len(fpn) < 3:
            raise RuntimeError("Pinned EdgeTAM configuration did not return three FPN levels")
        return fpn[2], fpn[0], fpn[1]


class MemoryEncoderPerceiverWrapper(torch.nn.Module):
    """Exact sigmoid/binarised-mask memory encoding followed by 512x64 compression."""

    def __init__(self, model: torch.nn.Module):
        super().__init__()
        self.model = model
        self.register_buffer("sigmoid_scale", torch.tensor(float(model.sigmoid_scale_for_mem_enc)))
        self.register_buffer("sigmoid_bias", torch.tensor(float(model.sigmoid_bias_for_mem_enc)))
        embed = model.no_obj_embed_spatial
        self.register_buffer(
            "no_obj_embed_spatial",
            embed.detach().clone() if embed is not None else torch.zeros(1, model.mem_dim),
        )
        self.has_no_obj_embed_spatial = embed is not None

    def forward(
        self,
        pix_feat: torch.Tensor,
        mask_logits: torch.Tensor,
        object_score_logits: torch.Tensor,
        mask_mode: torch.Tensor,
    ):
        # mask_mode is a runtime scalar: 0=sigmoid tracking mask, 1=binarised point mask.
        # Arithmetic selection keeps both paths in the converted graph.
        binary = (mask_logits > 0).to(pix_feat.dtype)
        mask = mask_mode.reshape(1, 1, 1, 1) * binary + (1.0 - mask_mode.reshape(1, 1, 1, 1)) * torch.sigmoid(mask_logits)
        mask = mask * self.sigmoid_scale + self.sigmoid_bias
        encoded = self.model.memory_encoder(pix_feat, mask, skip_mask_sigmoid=True)
        features = encoded["vision_features"]
        # Keep the official gate in the graph even when this checkpoint has no
        # learned spatial no-object embedding (the registered zero buffer makes
        # that configuration an exact no-op while retaining the runtime input).
        is_obj_appearing = (object_score_logits > 0).to(features.dtype)
        features = features + (1.0 - is_obj_appearing[..., None, None]) * self.no_obj_embed_spatial[..., None, None]
        features, positions = self.model.spatial_perceiver(features, encoded["vision_pos_enc"][0])
        return features, positions


def load_model(source: Path, checkpoint: Path) -> torch.nn.Module:
    GlobalHydra.instance().clear()
    sys.path.insert(0, str(source))
    with initialize_config_dir(config_dir=str(source / "sam2" / "configs"), version_base=None):
        config = compose(config_name="edgetam")
        OmegaConf.resolve(config)
        model = instantiate(config.model, _recursive_=True)
    weights = torch.load(checkpoint, map_location="cpu", weights_only=True)["model"]
    missing, unexpected = model.load_state_dict(weights)
    if missing or unexpected:
        raise RuntimeError(f"Checkpoint mismatch: missing={missing}, unexpected={unexpected}")
    return model.eval()


def max_deltas(expected, actual, outputs):
    deltas = [np.abs(exp - actual[name]) for exp, name in zip(expected, outputs)]
    return {
        "maxAbsoluteError": float(max(delta.max() for delta in deltas)),
        "meanAbsoluteError": float(np.mean([delta.mean() for delta in deltas])),
        "outputShapes": {name: list(value.shape) for name, value in zip(outputs, expected)},
    }


def convert_and_compare(wrapper, reference, inputs, names, outputs, output_path: Path, alternate_inputs=None):
    wrapper.eval()
    with torch.no_grad():
        expected = tuple(x.detach().cpu().numpy() for x in wrapper(*inputs))
        reference_values = tuple(x.detach().cpu().numpy() for x in reference)
    traced = torch.jit.trace(wrapper, inputs, strict=True)
    converted = ct.convert(
        traced,
        inputs=[ct.TensorType(name=name, shape=tuple(value.shape), dtype=np.float32) for name, value in zip(names, inputs)],
        outputs=[ct.TensorType(name=name) for name in outputs],
        minimum_deployment_target=ct.target.iOS16,
        compute_units=ct.ComputeUnit.ALL,
        compute_precision=ct.precision.FLOAT32,
        convert_to="mlprogram",
    )
    converted.save(str(output_path))
    actual = converted.predict({name: value.detach().cpu().numpy() for name, value in zip(names, inputs)})
    converted_errors = max_deltas(expected, actual, outputs)
    reference_errors = max_deltas(reference_values, {name: value for name, value in zip(outputs, expected)}, outputs)
    result = {
        "path": output_path.name,
        "convertedVsWrapper": converted_errors,
        "wrapperVsOfficial": reference_errors,
    }
    if alternate_inputs is not None:
        with torch.no_grad():
            alternate_expected = tuple(value.detach().cpu().numpy() for value in wrapper(*alternate_inputs))
        alternate_actual = converted.predict({name: value.detach().cpu().numpy() for name, value in zip(names, alternate_inputs)})
        result["alternateRuntimeModeVsWrapper"] = max_deltas(alternate_expected, alternate_actual, outputs)
    return result


def official_image_outputs(model, image):
    with torch.no_grad():
        fpn = model.forward_image(image)["backbone_fpn"]
        return fpn[2], fpn[0], fpn[1]


def official_memory_outputs(model, pix, mask_logits, object_score_logits, binarize):
    current_vision = [pix.flatten(2).permute(2, 0, 1)]
    old_binarize = model.binarize_mask_from_pts_for_mem_enc
    model.binarize_mask_from_pts_for_mem_enc = bool(binarize)
    try:
        with torch.no_grad():
            features, positions = model._encode_new_memory(
                current_vision_feats=current_vision,
                feat_sizes=[(pix.shape[-2], pix.shape[-1])],
                pred_masks_high_res=mask_logits,
                object_score_logits=object_score_logits,
                is_mask_from_pts=bool(binarize),
            )
    finally:
        model.binarize_mask_from_pts_for_mem_enc = old_binarize
    return features, positions[0]


def git_revision(source: Path):
    try:
        return subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def run_component(model, source, checkpoint, output, component, image, pix, mask, score):
    component_dir = output / component
    component_dir.mkdir(parents=True, exist_ok=True)
    manifest = {
        "status": "started",
        "component": component,
        "inputAlreadyNormalised": component == "image",
        "maskModes": ["sigmoid_tracking", "binarized_point"] if component == "memory" else [],
        "mean": MEAN,
        "std": STD,
        "computePrecision": "FLOAT32",
        "minimumDeploymentTarget": "iOS16",
        "computeUnits": "ALL",
        "checkpointSHA256": sha256(checkpoint),
        "wrapperSHA256": sha256(Path(__file__).resolve()),
        "upstreamRevision": git_revision(source),
        "criteria": "Synthetic component numerical parity only; no video, phone, or tracking-quality claim.",
    }
    started = time.perf_counter()
    try:
        if component == "image":
            inputs = (image,)
            reference = official_image_outputs(model, image)
            result = convert_and_compare(
                ImageEncoderWrapper(model), reference, inputs,
                ("image_normalised",),
                ("vision_features", "high_res_feat_0", "high_res_feat_1"),
                component_dir / "edgetam_image_encoder.mlpackage",
            )
            manifest.update({"inputShapes": [list(image.shape)], "outputShapes": result["convertedVsWrapper"]["outputShapes"], "result": result})
        else:
            mode_results = {}
            official_checks = {}
            for mode_name, mode_value in (("sigmoid_tracking", 0.0), ("binarized_point", 1.0)):
                mode = torch.tensor([mode_value], dtype=torch.float32)
                inputs = (pix, mask, score, mode)
                reference = official_memory_outputs(model, pix, mask, score, bool(mode_value))
                wrapper = MemoryEncoderPerceiverWrapper(model)
                mode_results[mode_name] = convert_and_compare(
                    wrapper, reference, inputs,
                    ("pix_feat", "mask_logits", "object_score_logits", "mask_mode"),
                    ("memory_features", "memory_positions"),
                    component_dir / f"edgetam_memory_encoder_perceiver_{mode_name}.mlpackage",
                    alternate_inputs=(pix, mask, score, torch.tensor([1.0 - mode_value], dtype=torch.float32)),
                )
                score_checks = {}
                for score_value in (1.0, -1.0):
                    score_input = torch.tensor([[score_value]], dtype=torch.float32)
                    runtime_inputs = (pix, mask, score_input, mode)
                    with torch.no_grad():
                        wrapper_output = tuple(value.detach().cpu().numpy() for value in wrapper(*runtime_inputs))
                    official_output = official_memory_outputs(model, pix, mask, score_input, bool(mode_value))
                    official_numpy = tuple(value.detach().cpu().numpy() for value in official_output)
                    score_checks[str(score_value)] = max_deltas(
                        official_numpy,
                        {name: value for name, value in zip(("memory_features", "memory_positions"), wrapper_output)},
                        ("memory_features", "memory_positions"),
                    )
                official_checks[mode_name] = score_checks
            manifest.update({
                "inputShapes": [list(pix.shape), list(mask.shape), list(score.shape), [1]],
                "objectScoreLogits": {"shape": list(score.shape), "valuesTested": [1.0, -1.0]},
                "noObjEmbedSpatialPresent": model.no_obj_embed_spatial is not None,
                "storedBFloat16MemoryFeatures": "Caller responsibility; this component preserves float32 outputs.",
                "outputShapes": mode_results["sigmoid_tracking"]["convertedVsWrapper"]["outputShapes"],
                "wrapperVsOfficialByObjectScore": official_checks,
                "results": mode_results,
            })
        manifest["status"] = "success"
    except Exception as error:
        manifest.update({"status": "failed", "errorType": type(error).__name__, "error": str(error)})
        (component_dir / "traceback.txt").write_text(traceback.format_exc())
    manifest["elapsedSeconds"] = time.perf_counter() - started
    (component_dir / "evidence.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--component", choices=("image", "memory", "all"), default="all")
    parser.add_argument("--binarize-mask", action="store_true", help="Deprecated compatibility flag; both runtime mask modes are exported.")
    args = parser.parse_args()
    source, checkpoint, output = external(args.source, "EdgeTAM source"), external(args.checkpoint, "EdgeTAM checkpoint"), external(args.output_dir, "Probe output")
    if not source.is_dir() or not checkpoint.is_file(): raise SystemExit("Pinned source and checkpoint are required")
    output.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    try:
        torch.manual_seed(7711); np.random.seed(7711)
        model = load_model(source, checkpoint)
        image = torch.randn(1, 3, 1024, 1024, dtype=torch.float32)
        pix = torch.randn(1, 256, 64, 64, dtype=torch.float32)
        mask = torch.randn(1, 1, 1024, 1024, dtype=torch.float32)
        score = torch.tensor([[1.0]], dtype=torch.float32)
        components = {}
        if args.component in ("image", "all"):
            components["image"] = run_component(model, source, checkpoint, output, "image", image, pix, mask, score)
        if args.component in ("memory", "all"):
            components["memory"] = run_component(model, source, checkpoint, output, "memory", image, pix, mask, score)
        evidence = {
            "status": "success" if all(item["status"] == "success" for item in components.values()) else "failed",
            "component": args.component,
            "components": {key: {"status": value["status"], "evidence": f"{key}/evidence.json"} for key, value in components.items()},
            "torch": torch.__version__,
            "coremltools": ct.__version__,
            "numpy": np.__version__,
            "upstreamRevision": git_revision(source),
            "checkpointSHA256": sha256(checkpoint),
            "wrapperSHA256": sha256(Path(__file__).resolve()),
            "criteria": "Synthetic component numerical parity only; no video, phone, or tracking-quality claim.",
        }
    except Exception as error:
        evidence = {"status": "failed", "component": args.component, "errorType": type(error).__name__, "error": str(error)}
        (output / "traceback.txt").write_text(traceback.format_exc())
    evidence["elapsedSeconds"] = time.perf_counter() - started
    (output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({key: evidence[key] for key in ("status", "component", "elapsedSeconds")}))
    return 0 if evidence["status"] == "success" else 1


if __name__ == "__main__":
    raise SystemExit(main())
