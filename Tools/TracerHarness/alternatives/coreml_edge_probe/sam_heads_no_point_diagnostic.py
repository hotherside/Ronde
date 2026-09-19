#!/usr/bin/env python3
"""Diagnose EdgeTAM SAM no-point prompt conversion without changing semantics."""

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


class SAMHeadStages(torch.nn.Module):
    """Upstream prompt encoder and decoder before and after source score gating."""

    def __init__(self, model: torch.nn.Module):
        super().__init__()
        self.model = model

    def forward(self, backbone: torch.Tensor, s0: torch.Tensor, s1: torch.Tensor, coords: torch.Tensor, labels: torch.Tensor):
        sparse, dense = self.model.sam_prompt_encoder(
            points=(coords, labels), boxes=None, masks=None
        )
        raw_masks, raw_ious, raw_tokens, raw_object_score = self.model.sam_mask_decoder(
            image_embeddings=backbone, image_pe=self.model.sam_prompt_encoder.get_dense_pe(),
            sparse_prompt_embeddings=sparse, dense_prompt_embeddings=dense,
            multimask_output=True, repeat_image=False, high_res_features=[s0, s1],
        )
        final = self.model._forward_sam_heads(
            backbone_features=backbone,
            point_inputs={"point_coords": coords, "point_labels": labels},
            mask_inputs=None, high_res_features=[s0, s1], multimask_output=True,
        )
        # Raw decoder candidates precede the source no-object clip. final[6] is
        # returned after that source method's score computation.
        return sparse, dense, raw_masks, raw_ious, raw_tokens, raw_object_score, final[3], final[6]


def direct_stages(model: torch.nn.Module, features: tuple[torch.Tensor, ...], coords: torch.Tensor, labels: torch.Tensor, no_point: bool):
    inputs = None if no_point else {"point_coords": coords, "point_labels": labels}
    # Model method creates the same zero/-1 input for no point. Construct the
    # prompt-encoder side explicitly from that source-equivalent tensor.
    if inputs is None:
        coords = torch.zeros((1, 1, 2), dtype=torch.float32)
        labels = -torch.ones((1, 1), dtype=torch.int32)
    sparse, dense = model.sam_prompt_encoder(points=(coords, labels), boxes=None, masks=None)
    raw = model.sam_mask_decoder(
        image_embeddings=features[0], image_pe=model.sam_prompt_encoder.get_dense_pe(),
        sparse_prompt_embeddings=sparse, dense_prompt_embeddings=dense,
        multimask_output=True, repeat_image=False, high_res_features=[features[1], features[2]],
    )
    final = model._forward_sam_heads(backbone_features=features[0], point_inputs=inputs, mask_inputs=None, high_res_features=[features[1], features[2]], multimask_output=True)
    return sparse, dense, raw[0], raw[1], raw[2], raw[3], final[3], final[6]


NAMES = ("sparse", "dense", "raw_masks", "raw_ious", "raw_tokens", "raw_object_score", "final_low_best", "final_object_score")


def errors(expected, actual):
    return {
        name: {"maxAbsoluteError": float((left - right).abs().max()), "meanAbsoluteError": float((left - right).abs().mean())}
        for name, left, right in zip(NAMES, expected, actual)
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    source, checkpoint, output = external(args.source, "source"), external(args.checkpoint, "checkpoint"), external(args.output_dir, "output")
    output.mkdir(parents=True, exist_ok=True)
    evidence = {"component": "SAM heads no-point diagnostic", "criteria": "Synthetic component diagnostic only; no tracker-quality claim.", "torch": torch.__version__, "numpy": np.__version__, "coremltools": ct.__version__, "computePrecision": "FLOAT32", "wrapperSHA256": sha256(Path(__file__).resolve()), "checkpointSHA256": sha256(checkpoint), "runtimePrompts": {"onePoint": {"coords": [512.0, 512.0], "label": 1}, "noPoint": {"coords": [0.0, 0.0], "label": -1}}}
    started = time.perf_counter()
    try:
        model = load_model(source, checkpoint)
        wrapper = SAMHeadStages(model).eval()
        prompts = {"onePoint": (torch.tensor([[[512.0, 512.0]]]), torch.tensor([[1]], dtype=torch.int32), False), "noPoint": (torch.zeros((1, 1, 2)), -torch.ones((1, 1), dtype=torch.int32), True)}
        with torch.no_grad():
            features = make_representative_features(model)
            traced = torch.jit.trace(wrapper, (*features, prompts["onePoint"][0], prompts["onePoint"][1]), strict=True)
            torch_parity = {}
            for name, (coords, labels, no_point) in prompts.items():
                torch_parity[name] = errors(direct_stages(model, features, coords, labels, no_point), traced(*features, coords, labels))
        evidence["originalVsTracedTorch"] = torch_parity
        if max(metric["maxAbsoluteError"] for branch in torch_parity.values() for metric in branch.values()) > 1e-4:
            raise RuntimeError("Tracing changes a SAM prompt branch before Core ML conversion")
        converted = ct.convert(
            traced,
            inputs=[ct.TensorType(name="backbone", shape=(1, 256, 64, 64), dtype=np.float32), ct.TensorType(name="s0", shape=(1, 32, 256, 256), dtype=np.float32), ct.TensorType(name="s1", shape=(1, 64, 128, 128), dtype=np.float32), ct.TensorType(name="coords", shape=(1, 1, 2), dtype=np.float32), ct.TensorType(name="labels", shape=(1, 1), dtype=np.int32)],
            outputs=[ct.TensorType(name=name) for name in NAMES], minimum_deployment_target=ct.target.iOS16, compute_units=ct.ComputeUnit.ALL, compute_precision=ct.precision.FLOAT32, convert_to="mlprogram",
        )
        package = output / "edgetam_sam_heads_no_point_diagnostic.mlpackage"
        converted.save(str(package))
        coreml_parity = {}
        for name, (coords, labels, _) in prompts.items():
            expected = traced(*features, coords, labels)
            values = converted.predict({"backbone": features[0].numpy(), "s0": features[1].numpy(), "s1": features[2].numpy(), "coords": coords.numpy(), "labels": labels.numpy()})
            actual = tuple(torch.from_numpy(values[key]) for key in NAMES)
            coreml_parity[name] = errors(expected, actual)
        evidence.update({"status": "success", "modelPath": package.name, "coreMLVsTracedTorch": coreml_parity})
    except Exception as error:
        evidence.update({"status": "failed", "errorType": type(error).__name__, "error": str(error)})
        (output / "traceback.txt").write_text(traceback.format_exc())
    evidence["elapsedSeconds"] = time.perf_counter() - started
    (output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({key: evidence[key] for key in ("status", "elapsedSeconds")}))
    return 0 if evidence["status"] == "success" else 1


if __name__ == "__main__":
    raise SystemExit(main())
