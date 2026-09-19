#!/usr/bin/env python3
"""Exact one-object EdgeTAM memory attention with variable history length.

This extends the reviewed fixed-state real-pair wrapper to 1..7 spatial
memories and 1..16 object pointers. The caller must supply whole 512-token
spatial memories and whole four-token pointers. No padding tokens are added.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys
import time
import traceback

import coremltools as ct
import numpy as np
import torch
import torch.nn.functional as F

from full_memory_attention_real_pair_probe import FixedRoPELayer, external, load_model, real_pair, sha256


class FlexibleRoPELayer(FixedRoPELayer):
    def forward(self, current, memory, memory_position, spatial_length):
        normalised = self.norm1(current)
        q = real_pair(self.heads(self.self_q_proj(normalised)), self.self_cosine, self.self_sine)
        k = real_pair(self.heads(self.self_k_proj(normalised)), self.self_cosine, self.self_sine)
        v = self.heads(self.self_v_proj(normalised))
        current = current + self.self_out_proj(self.unheads(F.scaled_dot_product_attention(q, k, v, dropout_p=0.0)))

        normalised = self.norm2(current)
        q = real_pair(self.heads(self.cross_q_proj(normalised)), self.cross_q_cosine, self.cross_q_sine)
        projected_k = self.heads(self.cross_k_proj(memory + memory_position))
        spatial_k = projected_k[:, :, :spatial_length, :]
        pointer_k = projected_k[:, :, spatial_length:, :]
        frames = spatial_k.reshape(1, 1, -1, 512, 256)
        unrotated = frames[:, :, :, :256, :]
        rotated_flat = frames[:, :, :, 256:, :].reshape(1, 1, -1, 256)
        rotated = real_pair(
            rotated_flat,
            self.cross_k_cosine[:, :, :spatial_length // 2, :, :],
            self.cross_k_sine[:, :, :spatial_length // 2, :, :],
        ).reshape(1, 1, -1, 256, 256)
        k = torch.cat((torch.cat((unrotated, rotated), dim=3).reshape(1, 1, -1, 256), pointer_k), dim=2)
        v = self.heads(self.cross_v_proj(memory))
        current = current + self.cross_out_proj(self.unheads(F.scaled_dot_product_attention(q, k, v, dropout_p=0.0)))
        return current + self.linear2(torch.relu(self.linear1(self.norm3(current))))


class FlexibleMemoryAttention(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        attention = model.memory_attention
        frequency = attention.layers[0].self_attn.compute_cis(end_x=64, end_y=64)
        self.layer0 = FlexibleRoPELayer(attention.layers[0], frequency)
        self.layer1 = FlexibleRoPELayer(attention.layers[1], frequency)
        self.norm = attention.norm

    def forward(self, current_features, current_position, spatial_memory, spatial_memory_position, object_pointer_tokens):
        current = current_features.flatten(2).transpose(1, 2) + 0.1 * current_position.flatten(2).transpose(1, 2)
        memory = torch.cat((spatial_memory, object_pointer_tokens), dim=1)
        position = torch.cat((spatial_memory_position, torch.zeros_like(object_pointer_tokens)), dim=1)
        length = spatial_memory.shape[1]
        current = self.layer0(current, memory, position, length)
        current = self.layer1(current, memory, position, length)
        return self.norm(current).transpose(1, 2).reshape(1, 256, 64, 64)


def original(model, inputs):
    feat, pos, spatial, spatial_pos, pointers = inputs
    return model.memory_attention(
        curr=feat.flatten(2).permute(2, 0, 1), curr_pos=pos.flatten(2).permute(2, 0, 1),
        memory=torch.cat((spatial, pointers), dim=1).permute(1, 0, 2),
        memory_pos=torch.cat((spatial_pos, torch.zeros_like(pointers)), dim=1).permute(1, 0, 2),
        num_obj_ptr_tokens=pointers.shape[1], num_spatial_mem=spatial.shape[1] // 512,
    ).permute(1, 2, 0).reshape(1, 256, 64, 64)


def delta(expected, actual):
    difference = np.abs(expected - actual)
    return {"maxAbsoluteError": float(difference.max()), "meanAbsoluteError": float(difference.mean())}


def package_digest(path):
    import hashlib
    manifest = "".join(f"{p.relative_to(path).as_posix()}\t{sha256(p)}\n" for p in sorted(path.rglob("*")) if p.is_file())
    return hashlib.sha256(manifest.encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    source, checkpoint, out = external(args.source, "source"), external(args.checkpoint, "checkpoint"), external(args.output_dir, "output")
    if not source.is_dir() or not checkpoint.is_file():
        raise SystemExit("Existing pinned source and checkpoint are required")
    if out.exists():
        raise SystemExit("Refusing to overwrite existing probe output")
    out.mkdir(parents=True)
    sys.path.insert(0, str(source))
    evidence = {
        "component": "one-object variable-history memory attention", "status": "started",
        "criteria": "Synthetic numerical parity, not full video or device evidence",
        "upstreamCommit": subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip(),
        "python": sys.version.split()[0], "torch": torch.__version__, "numpy": np.__version__, "coremltools": ct.__version__,
        "wrapperSHA256": sha256(Path(__file__).resolve()), "fixedHelperSHA256": sha256(Path(__file__).with_name("full_memory_attention_real_pair_probe.py")),
        "checkpointSHA256": sha256(checkpoint), "computePrecision": "FLOAT32", "computeUnits": "ALL", "minimumDeploymentTarget": "iOS16",
        "callerConstraints": "Spatial lengths 512..3584 in multiples of 512; equal feature/position length; pointer lengths 4..64 in multiples of four. No padding. Initial no-memory frame bypasses attention upstream.",
        "bf16StoredMemoryRoundtrip": "Caller responsibility before attention, as in original video predictor",
    }
    started = time.perf_counter()
    try:
        model = load_model(source, checkpoint)
        wrapper = FlexibleMemoryAttention(model).eval()
        cases = []
        with torch.no_grad():
            for i, (nmem, nptr) in enumerate(((1, 1), (3, 3), (7, 7), (7, 16))):
                torch.manual_seed(7711 + i)
                shapes = ((1, 256, 64, 64), (1, 256, 64, 64), (1, nmem * 512, 64), (1, nmem * 512, 64), (1, nptr * 4, 64))
                values = tuple(torch.randn(s, dtype=torch.float32) for s in shapes)
                expected = original(model, values).numpy()
                wrapped = wrapper(*values).numpy()
                comparison = delta(expected, wrapped)
                cases.append((values, expected, {"spatialFrames": nmem, "objectPointers": nptr, "originalVsWrapper": comparison}))
                if comparison["maxAbsoluteError"] > 1e-4:
                    raise RuntimeError("Original-vs-wrapper parity failed")
            trace = torch.jit.trace(wrapper, cases[-1][0], strict=True)
            for values, expected, info in cases:
                info["originalVsTraced"] = delta(expected, trace(*values).numpy())
                if info["originalVsTraced"]["maxAbsoluteError"] > 1e-4:
                    raise RuntimeError("Variable-shape traced parity failed")
        evidence["pytorchParity"] = [x[2] for x in cases]
        names = ("current_features", "current_position", "spatial_memory", "spatial_memory_position", "object_pointer_tokens")
        spatial_dim = ct.RangeDim(lower_bound=512, upper_bound=3584, default=3584)
        pointer_dim = ct.RangeDim(lower_bound=4, upper_bound=64, default=64)
        shapes = ((1, 256, 64, 64), (1, 256, 64, 64), (1, spatial_dim, 64), (1, spatial_dim, 64), (1, pointer_dim, 64))
        converted = ct.convert(
            trace, inputs=[ct.TensorType(name=n, shape=s, dtype=np.float32) for n, s in zip(names, shapes)],
            outputs=[ct.TensorType(name="fused_features")], minimum_deployment_target=ct.target.iOS16,
            compute_units=ct.ComputeUnit.ALL, compute_precision=ct.precision.FLOAT32, convert_to="mlprogram",
        )
        package = out / "edgetam_variable_memory_attention.mlpackage"
        converted.save(str(package))
        evidence["packageSHA256"] = package_digest(package)
        evidence["coreMLParity"] = []
        for values, expected, info in cases:
            actual = converted.predict({name: value.numpy() for name, value in zip(names, values)})["fused_features"]
            comparison = delta(expected, actual)
            evidence["coreMLParity"].append({"spatialFrames": info["spatialFrames"], "objectPointers": info["objectPointers"], **comparison})
            if comparison["maxAbsoluteError"] > 1e-4:
                raise RuntimeError("Original-vs-CoreML parity failed")
        evidence["status"] = "success"
    except Exception as error:
        evidence.update(status="failed", errorType=type(error).__name__, error=str(error))
        (out / "traceback.txt").write_text(traceback.format_exc())
    evidence["elapsedSeconds"] = time.perf_counter() - started
    (out / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({key: evidence[key] for key in ("status", "component", "elapsedSeconds")}))
    return 0 if evidence["status"] == "success" else 1


if __name__ == "__main__":
    raise SystemExit(main())
