#!/usr/bin/env python3
"""Fixed-prompt EdgeTAM SAM-head Core ML component parity probe.

The wrapper calls the upstream `_forward_sam_heads` unchanged.  It exports the
valid one-point/no-point fixed shape by treating label -1 at (0, 0) as the
upstream method's own padded no-point input.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
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


def load_model(source: Path, checkpoint: Path) -> torch.nn.Module:
    # The checkpoint loads every backbone weight. Avoid an irrelevant remote
    # pretrained-weight lookup during construction.
    import sam2.modeling.backbones.timm as backbone_module

    original_create_model = backbone_module.create_model

    def local_backbone(*values, **kwargs):
        kwargs["pretrained"] = False
        return original_create_model(*values, **kwargs)

    backbone_module.create_model = local_backbone
    try:
        GlobalHydra.instance().clear()
        with initialize_config_dir(config_dir=str(source / "sam2" / "configs"), version_base=None):
            config = compose(config_name="edgetam")
            OmegaConf.resolve(config)
            model = instantiate(config.model, _recursive_=True)
    finally:
        backbone_module.create_model = original_create_model
    weights = torch.load(checkpoint, map_location="cpu", weights_only=True)["model"]
    missing, unexpected = model.load_state_dict(weights)
    if missing or unexpected:
        raise RuntimeError("Checkpoint did not exactly match the pinned EdgeTAM configuration")
    return model.eval()


class FixedPromptSAMHeads(torch.nn.Module):
    """Original prompt encoder and decoder, with multimask branch fixed true."""

    def __init__(self, model: torch.nn.Module):
        super().__init__()
        self.model = model

    def forward(
        self,
        backbone_features: torch.Tensor,
        high_res_s0: torch.Tensor,
        high_res_s1: torch.Tensor,
        point_coords: torch.Tensor,
        point_labels: torch.Tensor,
    ) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor]:
        outputs = self.model._forward_sam_heads(
            backbone_features=backbone_features,
            point_inputs={"point_coords": point_coords, "point_labels": point_labels},
            mask_inputs=None,
            high_res_features=[high_res_s0, high_res_s1],
            multimask_output=True,
        )
        return outputs[3], outputs[4], outputs[2], outputs[5], outputs[6]


def make_representative_features(model: torch.nn.Module) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    """Use the real encoder on a deterministic synthetic ImageNet-normalised image."""
    torch.manual_seed(7711)
    image = torch.rand(1, 3, 1024, 1024, dtype=torch.float32)
    mean = torch.tensor((0.485, 0.456, 0.406), dtype=torch.float32)[None, :, None, None]
    std = torch.tensor((0.229, 0.224, 0.225), dtype=torch.float32)[None, :, None, None]
    backbone_out = model.forward_image((image - mean) / std)
    features = backbone_out["backbone_fpn"]
    # forward_image has already projected these when high-res SAM is enabled.
    return features[-1], features[0], features[1]


def original_outputs(model: torch.nn.Module, features: tuple[torch.Tensor, ...], coords: torch.Tensor, labels: torch.Tensor, no_point: bool) -> tuple[torch.Tensor, ...]:
    inputs = None if no_point else {"point_coords": coords, "point_labels": labels}
    result = model._forward_sam_heads(
        backbone_features=features[0], point_inputs=inputs, mask_inputs=None,
        high_res_features=[features[1], features[2]], multimask_output=True,
    )
    return result[3], result[4], result[2], result[5], result[6]


def compare(expected: tuple[torch.Tensor, ...], actual: tuple[torch.Tensor, ...]) -> dict[str, float]:
    deltas = [torch.abs(left - right).max().item() for left, right in zip(expected, actual)]
    means = [torch.abs(left - right).mean().item() for left, right in zip(expected, actual)]
    return {"maxAbsoluteError": float(max(deltas)), "meanAbsoluteError": float(max(means))}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    source = external(args.source, "EdgeTAM source")
    checkpoint = external(args.checkpoint, "EdgeTAM checkpoint")
    output = external(args.output_dir, "probe output")
    if not source.is_dir() or not checkpoint.is_file():
        raise SystemExit("Pinned source and checkpoint are required")
    output.mkdir(parents=True, exist_ok=True)
    evidence = {
        "component": "EdgeTAM SAM prompt and mask heads, fixed valid one-point/no-point multimask branch",
        "criteria": "Synthetic component parity only; no video, memory update, or tracker-quality claim.",
        "upstreamCommit": subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip(),
        "licence": "Apache-2.0", "python": sys.version.split()[0], "torch": torch.__version__, "numpy": np.__version__, "coremltools": ct.__version__,
        "computePrecision": "FLOAT32", "computeUnits": "ALL", "minimumDeploymentTarget": "iOS16",
        "inputs": {"backboneFeatures": [1, 256, 64, 64], "highResS0": [1, 32, 256, 256], "highResS1": [1, 64, 128, 128], "pointCoords": [1, 1, 2], "pointLabels": [1, 1]},
        "outputs": {"lowBest256": [1, 1, 256, 256], "highBest1024": [1, 1, 1024, 1024], "ious": [1, 3], "objectPointer": [1, 256], "objectScore": [1, 1]},
        "wrapperSHA256": sha256(Path(__file__).resolve()), "checkpointSHA256": sha256(checkpoint),
        "samBaseSourceSHA256": sha256(source / "sam2" / "modeling" / "sam2_base.py"),
    }
    started = time.perf_counter()
    try:
        model = load_model(source, checkpoint)
        supplied = {"point_coords": torch.tensor([[[512.0, 512.0]]]), "point_labels": torch.tensor([[1]], dtype=torch.int32)}
        padded = {"point_coords": torch.zeros((1, 1, 2), dtype=torch.float32), "point_labels": -torch.ones((1, 1), dtype=torch.int32)}
        if not model._use_multimask(True, supplied) or not model._use_multimask(True, None):
            raise RuntimeError("Pinned configuration does not permit multimask for both one-point and no-point branches")
        with torch.no_grad():
            features = make_representative_features(model)
            wrapper = FixedPromptSAMHeads(model).eval()
            point_expected = original_outputs(model, features, supplied["point_coords"], supplied["point_labels"], no_point=False)
            none_expected = original_outputs(model, features, padded["point_coords"], padded["point_labels"], no_point=True)
            point_actual = wrapper(*features, supplied["point_coords"], supplied["point_labels"])
            none_actual = wrapper(*features, padded["point_coords"], padded["point_labels"])
            evidence["pytorchParity"] = {"onePoint": compare(point_expected, point_actual), "noPoint": compare(none_expected, none_actual)}
            if max(item["maxAbsoluteError"] for item in evidence["pytorchParity"].values()) > 1e-4:
                raise RuntimeError("Wrapped SAM heads did not meet the 1e-4 PyTorch equivalence criterion")
            traced = torch.jit.trace(wrapper, (*features, supplied["point_coords"], supplied["point_labels"]), strict=True)
        converted = ct.convert(
            traced,
            inputs=[
                ct.TensorType(name="backbone_features", shape=(1, 256, 64, 64), dtype=np.float32),
                ct.TensorType(name="high_res_s0", shape=(1, 32, 256, 256), dtype=np.float32),
                ct.TensorType(name="high_res_s1", shape=(1, 64, 128, 128), dtype=np.float32),
                ct.TensorType(name="point_coords", shape=(1, 1, 2), dtype=np.float32),
                ct.TensorType(name="point_labels", shape=(1, 1), dtype=np.int32),
            ],
            outputs=[ct.TensorType(name=name) for name in ("low_best_256", "high_best_1024", "ious", "object_pointer", "object_score")],
            minimum_deployment_target=ct.target.iOS16, compute_units=ct.ComputeUnit.ALL,
            compute_precision=ct.precision.FLOAT32, convert_to="mlprogram",
        )
        model_path = output / "edgetam_sam_heads_fixed_prompt.mlpackage"
        converted.save(str(model_path))
        prompt_results = {}
        for name, prompt in (("onePoint", supplied), ("noPoint", padded)):
            expected = wrapper(*features, prompt["point_coords"], prompt["point_labels"])
            values = converted.predict({"backbone_features": features[0].numpy(), "high_res_s0": features[1].numpy(), "high_res_s1": features[2].numpy(), "point_coords": prompt["point_coords"].numpy(), "point_labels": prompt["point_labels"].numpy()})
            actual = tuple(values[key] for key in ("low_best_256", "high_best_1024", "ious", "object_pointer", "object_score"))
            prompt_results[name] = compare(expected, tuple(torch.from_numpy(value) for value in actual))
        evidence.update({"status": "success", "modelPath": model_path.name, "coreMLParity": prompt_results})
    except Exception as error:
        evidence.update({"status": "failed", "errorType": type(error).__name__, "error": str(error)})
        (output / "traceback.txt").write_text(traceback.format_exc())
    evidence["elapsedSeconds"] = time.perf_counter() - started
    (output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({key: evidence[key] for key in ("status", "torch", "coremltools", "elapsedSeconds")}))
    return 0 if evidence["status"] == "success" else 1


if __name__ == "__main__":
    raise SystemExit(main())
