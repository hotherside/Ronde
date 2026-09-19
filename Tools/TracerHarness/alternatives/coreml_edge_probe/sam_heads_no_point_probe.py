#!/usr/bin/env python3
"""Exact EdgeTAM no-point SAM-head export; no runtime negative-label branch."""

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

from sam_heads_probe import external, load_model, make_representative_features, sha256


class FixedNoPointSAMHeads(torch.nn.Module):
    """Calls the source no-point branch, which creates its own zero/-1 padding."""

    def __init__(self, model: torch.nn.Module):
        super().__init__()
        self.model = model

    def forward(self, backbone: torch.Tensor, s0: torch.Tensor, s1: torch.Tensor):
        result = self.model._forward_sam_heads(
            backbone_features=backbone, point_inputs=None, mask_inputs=None,
            high_res_features=[s0, s1], multimask_output=True,
        )
        return result[3], result[4], result[2], result[5], result[6]


NAMES = ("low_best_256", "high_best_1024", "ious", "object_pointer", "object_score")


def stats(expected, actual):
    return {name: {"maxAbsoluteError": float((left - right).abs().max()), "meanAbsoluteError": float((left - right).abs().mean())} for name, left, right in zip(NAMES, expected, actual)}


def tree_hash(root: Path) -> str:
    digest = hashlib.sha256()
    for item in sorted(path for path in root.rglob("*") if path.is_file()):
        digest.update(item.relative_to(root).as_posix().encode() + b"\0")
        digest.update(sha256(item).encode() + b"\n")
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    source, checkpoint, output = external(args.source, "source"), external(args.checkpoint, "checkpoint"), external(args.output_dir, "output")
    output.mkdir(parents=True, exist_ok=True)
    evidence = {"component": "EdgeTAM SAM heads fixed no-point source branch", "criteria": "Synthetic component parity only; no tracker-quality claim.", "sourcePromptMode": "point_inputs=None; upstream creates zero coordinates and -1 padding", "torch": torch.__version__, "numpy": np.__version__, "coremltools": ct.__version__, "computePrecision": "FLOAT32", "computeUnits": "ALL", "minimumDeploymentTarget": "iOS16", "inputs": {"backbone": [1, 256, 64, 64], "s0": [1, 32, 256, 256], "s1": [1, 64, 128, 128]}, "outputs": {"lowBest256": [1, 1, 256, 256], "highBest1024": [1, 1, 1024, 1024], "ious": [1, 3], "objectPointer": [1, 256], "objectScore": [1, 1]}, "wrapperSHA256": sha256(Path(__file__).resolve()), "checkpointSHA256": sha256(checkpoint)}
    started = time.perf_counter()
    try:
        model = load_model(source, checkpoint)
        wrapper = FixedNoPointSAMHeads(model).eval()
        with torch.no_grad():
            features = make_representative_features(model)
            expected = model._forward_sam_heads(backbone_features=features[0], point_inputs=None, mask_inputs=None, high_res_features=[features[1], features[2]], multimask_output=True)
            expected = (expected[3], expected[4], expected[2], expected[5], expected[6])
            actual = wrapper(*features)
            evidence["originalVsWrapperTorch"] = stats(expected, actual)
            if max(value["maxAbsoluteError"] for value in evidence["originalVsWrapperTorch"].values()) > 1e-4:
                raise RuntimeError("Fixed no-point wrapper differs from the original method")
            traced = torch.jit.trace(wrapper, features, strict=True)
            evidence["originalVsTracedTorch"] = stats(expected, traced(*features))
            if max(value["maxAbsoluteError"] for value in evidence["originalVsTracedTorch"].values()) > 1e-4:
                raise RuntimeError("Fixed no-point trace differs from the original method")
        converted = ct.convert(traced, inputs=[ct.TensorType(name="backbone", shape=(1, 256, 64, 64), dtype=np.float32), ct.TensorType(name="s0", shape=(1, 32, 256, 256), dtype=np.float32), ct.TensorType(name="s1", shape=(1, 64, 128, 128), dtype=np.float32)], outputs=[ct.TensorType(name=name) for name in NAMES], minimum_deployment_target=ct.target.iOS16, compute_units=ct.ComputeUnit.ALL, compute_precision=ct.precision.FLOAT32, convert_to="mlprogram")
        package = output / "edgetam_sam_heads_no_point.mlpackage"
        converted.save(str(package))
        values = converted.predict({"backbone": features[0].numpy(), "s0": features[1].numpy(), "s1": features[2].numpy()})
        evidence.update({"status": "success", "modelPath": package.name, "modelBundleSHA256": tree_hash(package), "coreMLVsTracedTorch": stats(traced(*features), tuple(torch.from_numpy(values[key]) for key in NAMES))})
    except Exception as error:
        evidence.update({"status": "failed", "errorType": type(error).__name__, "error": str(error)})
        (output / "traceback.txt").write_text(traceback.format_exc())
    evidence["elapsedSeconds"] = time.perf_counter() - started
    (output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({key: evidence[key] for key in ("status", "elapsedSeconds")}))
    return 0 if evidence["status"] == "success" else 1


if __name__ == "__main__":
    raise SystemExit(main())
