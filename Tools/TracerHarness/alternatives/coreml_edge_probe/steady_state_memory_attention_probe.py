#!/usr/bin/env python3
"""Synthetic fixed-shape Core ML feasibility probe for EdgeTAM memory attention.

This probe does not process video or assess tracker quality. It loads the pinned
Apache-2.0 EdgeTAM checkpoint, exports the real temporal attention module with
one-object steady-state shapes, and compares deterministic synthetic tensors.
"""

from __future__ import annotations

import argparse
import hashlib
import json
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


class FixedOneObjectSteadyMemoryAttention(torch.nn.Module):
    """Real EdgeTAM memory attention with fixed seven-frame/16-pointer state.

    The state is already semantically full: seven 512-token spatial memories
    plus sixteen 256D pointers split into four 64D tokens each. It never pads a
    shorter history, so it only represents steady-state video frames.
    """

    def __init__(self, model: torch.nn.Module):
        super().__init__()
        self.attention = model.memory_attention

    def forward(
        self,
        current_features: torch.Tensor,  # 1,256,64,64
        current_position: torch.Tensor,  # 1,256,64,64
        spatial_memory: torch.Tensor,  # 1,3584,64
        spatial_memory_position: torch.Tensor,  # 1,3584,64
        object_pointer_tokens: torch.Tensor,  # 1,64,64
    ) -> torch.Tensor:
        current = current_features.flatten(2).permute(2, 0, 1)
        current_pos = current_position.flatten(2).permute(2, 0, 1)
        memory = torch.cat((spatial_memory, object_pointer_tokens), dim=1).permute(1, 0, 2)
        pointer_position = torch.zeros_like(object_pointer_tokens)
        memory_pos = torch.cat((spatial_memory_position, pointer_position), dim=1).permute(1, 0, 2)
        fused = self.attention(
            curr=current,
            curr_pos=current_pos,
            memory=memory,
            memory_pos=memory_pos,
            num_obj_ptr_tokens=64,
            num_spatial_mem=7,
        )
        return fused.permute(1, 2, 0).reshape(1, 256, 64, 64)


def load_model(source: Path, checkpoint: Path) -> torch.nn.Module:
    GlobalHydra.instance().clear()
    with initialize_config_dir(config_dir=str(source / "sam2" / "configs"), version_base=None):
        config = compose(config_name="edgetam")
        OmegaConf.resolve(config)
        model = instantiate(config.model, _recursive_=True)
    weights = torch.load(checkpoint, map_location="cpu", weights_only=True)["model"]
    missing, unexpected = model.load_state_dict(weights)
    if missing or unexpected:
        raise RuntimeError("Checkpoint did not exactly match the pinned EdgeTAM configuration")
    return model.eval()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    source = external(args.source, "EdgeTAM source")
    checkpoint = external(args.checkpoint, "EdgeTAM checkpoint")
    output = external(args.output_dir, "Probe output")
    if not source.is_dir() or not checkpoint.is_file():
        raise SystemExit("Pinned source and checkpoint are required")
    output.mkdir(parents=True, exist_ok=True)
    source_file = source / "sam2" / "modeling" / "memory_attention.py"
    try:
        import subprocess
        upstream_commit = subprocess.check_output(
            ["git", "-C", str(source), "rev-parse", "HEAD"], text=True
        ).strip()
    except Exception:
        upstream_commit = "unavailable"
    evidence = {
        "upstreamCommit": upstream_commit,
        "licence": "Apache-2.0",
        "component": "fixed one-object steady-state EdgeTAM memory attention",
        "seed": 7711,
        "inputShapes": [[1, 256, 64, 64], [1, 256, 64, 64], [1, 3584, 64], [1, 3584, 64], [1, 64, 64]],
        "spatialMemoryFrames": 7,
        "spatialTokensPerFrame": 512,
        "objectPointerTokens": 64,
        "computeUnits": "ALL",
        "minimumDeploymentTarget": "iOS16",
        "computePrecision": "FLOAT32",
        "python": sys.version.split()[0],
        "torch": torch.__version__,
        "coremltools": ct.__version__,
        "numpy": np.__version__,
        "wrapperSHA256": sha256(Path(__file__).resolve()),
        "memoryAttentionSourceSHA256": sha256(source_file),
        "checkpointSHA256": sha256(checkpoint),
        "criteria": "Synthetic component parity only; no image, mask, video, or flight-quality claim.",
    }
    started = time.perf_counter()
    try:
        torch.manual_seed(7711)
        np.random.seed(7711)
        model = load_model(source, checkpoint)
        wrapper = FixedOneObjectSteadyMemoryAttention(model).eval()
        shapes = [(1, 256, 64, 64), (1, 256, 64, 64), (1, 3584, 64), (1, 3584, 64), (1, 64, 64)]
        names = ("current_features", "current_position", "spatial_memory", "spatial_memory_position", "object_pointer_tokens")
        inputs = tuple(torch.randn(shape, dtype=torch.float32) for shape in shapes)
        with torch.no_grad():
            torch_output = wrapper(*inputs).cpu().numpy()
            traced = torch.jit.trace(wrapper, inputs, strict=True)
        converted = ct.convert(
            traced,
            inputs=[ct.TensorType(name=name, shape=shape, dtype=np.float32) for name, shape in zip(names, shapes)],
            outputs=[ct.TensorType(name="fused_features")],
            minimum_deployment_target=ct.target.iOS16,
            compute_units=ct.ComputeUnit.ALL,
            compute_precision=ct.precision.FLOAT32,
            convert_to="mlprogram",
        )
        model_path = output / "edgetam_fixed_steady_memory_attention.mlpackage"
        converted.save(str(model_path))
        coreml_output = converted.predict({name: tensor.cpu().numpy() for name, tensor in zip(names, inputs)})["fused_features"]
        delta = np.abs(torch_output - coreml_output)
        evidence.update({
            "status": "success",
            "torchDType": "float32",
            "coreMLDType": "float32",
            "modelPath": model_path.name,
            "maxAbsoluteError": float(delta.max()),
            "meanAbsoluteError": float(delta.mean()),
        })
    except Exception as error:
        evidence.update({
            "status": "failed",
            "errorType": type(error).__name__,
            "error": str(error),
        })
        (output / "traceback.txt").write_text(traceback.format_exc())
    evidence["elapsedSeconds"] = time.perf_counter() - started
    (output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({key: evidence[key] for key in ("status", "torch", "coremltools", "numpy", "elapsedSeconds")}))
    return 0 if evidence["status"] == "success" else 1


if __name__ == "__main__":
    raise SystemExit(main())
