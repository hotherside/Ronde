#!/usr/bin/env python3
"""Fixed-state EdgeTAM memory-attention Core ML parity probe.

This keeps the original two attention layers and every learned projection.  It
re-expresses only their complex RoPE operations as real even/odd-pair products
for the fixed one-object steady state: 64x64 current tokens, seven 512-token
spatial memories, and 64 unrotated object-pointer tokens.
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
import torch.nn.functional as F
from hydra import compose, initialize_config_dir
from hydra.core.global_hydra import GlobalHydra
from hydra.utils import instantiate
from omegaconf import OmegaConf


REPOSITORY = Path(__file__).resolve().parents[4]
CURRENT_TOKENS = 64 * 64
SPATIAL_FRAMES = 7
TOKENS_PER_SPATIAL_FRAME = 512
ROTATED_TOKENS_PER_FRAME = 256
POINTER_TOKENS = 64


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


def real_pair(value: torch.Tensor, cosine: torch.Tensor, sine: torch.Tensor) -> torch.Tensor:
    """Apply x * (cos + i sin) without complex operators."""
    pairs = value.float().reshape(*value.shape[:-1], value.shape[-1] // 2, 2)
    even, odd = pairs[..., 0:1], pairs[..., 1:2]
    rotated = torch.cat((even * cosine - odd * sine, even * sine + odd * cosine), dim=-1)
    return rotated.flatten(-2).type_as(value)


class FixedRoPELayer(torch.nn.Module):
    """One original EdgeTAM memory layer with its fixed RoPE tables in real form."""

    def __init__(self, source_layer: torch.nn.Module, self_frequency: torch.Tensor):
        super().__init__()
        self.norm1 = source_layer.norm1
        self.norm2 = source_layer.norm2
        self.norm3 = source_layer.norm3
        self.linear1 = source_layer.linear1
        self.linear2 = source_layer.linear2
        self.self_q_proj = source_layer.self_attn.q_proj
        self.self_k_proj = source_layer.self_attn.k_proj
        self.self_v_proj = source_layer.self_attn.v_proj
        self.self_out_proj = source_layer.self_attn.out_proj
        self.cross_q_proj = source_layer.cross_attn_image.q_proj
        self.cross_k_proj = source_layer.cross_attn_image.k_proj
        self.cross_v_proj = source_layer.cross_attn_image.v_proj
        self.cross_out_proj = source_layer.cross_attn_image.out_proj
        self.register_buffer("self_cosine", self_frequency.real.float().reshape(1, 1, CURRENT_TOKENS, 128, 1))
        self.register_buffer("self_sine", self_frequency.imag.float().reshape(1, 1, CURRENT_TOKENS, 128, 1))
        cross = source_layer.cross_attn_image
        self.register_buffer("cross_q_cosine", cross.freqs_cis_q.real.float().reshape(1, 1, CURRENT_TOKENS, 128, 1))
        self.register_buffer("cross_q_sine", cross.freqs_cis_q.imag.float().reshape(1, 1, CURRENT_TOKENS, 128, 1))
        # Repeat the actual one-frame table seven times. Keeping it flattened
        # avoids Core ML's rank-six constant limit without changing the source
        # frame ordering or the 256-token no-RoPE prefix in every memory frame.
        self.register_buffer("cross_k_cosine", cross.freqs_cis_k.real.float().repeat(SPATIAL_FRAMES, 1).reshape(1, 1, SPATIAL_FRAMES * ROTATED_TOKENS_PER_FRAME, 128, 1))
        self.register_buffer("cross_k_sine", cross.freqs_cis_k.imag.float().repeat(SPATIAL_FRAMES, 1).reshape(1, 1, SPATIAL_FRAMES * ROTATED_TOKENS_PER_FRAME, 128, 1))

    @staticmethod
    def heads(value: torch.Tensor) -> torch.Tensor:
        return value.reshape(1, value.shape[1], 1, 256).transpose(1, 2)

    @staticmethod
    def unheads(value: torch.Tensor) -> torch.Tensor:
        return value.transpose(1, 2).reshape(1, value.shape[2], 256)

    def forward(self, current: torch.Tensor, memory: torch.Tensor, memory_position: torch.Tensor) -> torch.Tensor:
        # Original _forward_sa: positional addition is disabled by edgetam.yaml.
        normalised = self.norm1(current)
        q = real_pair(self.heads(self.self_q_proj(normalised)), self.self_cosine, self.self_sine)
        k = real_pair(self.heads(self.self_k_proj(normalised)), self.self_cosine, self.self_sine)
        v = self.heads(self.self_v_proj(normalised))
        current = current + self.self_out_proj(self.unheads(F.scaled_dot_product_attention(q, k, v, dropout_p=0.0)))

        # Original _forward_ca: query position is disabled, key position is enabled.
        normalised = self.norm2(current)
        q = real_pair(self.heads(self.cross_q_proj(normalised)), self.cross_q_cosine, self.cross_q_sine)
        projected_k = self.heads(self.cross_k_proj(memory + memory_position))
        spatial_k = projected_k[:, :, : SPATIAL_FRAMES * TOKENS_PER_SPATIAL_FRAME, :]
        pointers_k = projected_k[:, :, SPATIAL_FRAMES * TOKENS_PER_SPATIAL_FRAME :, :]
        frames = spatial_k.reshape(1, 1, SPATIAL_FRAMES, TOKENS_PER_SPATIAL_FRAME, 256)
        unrotated = frames[:, :, :, :TOKENS_PER_SPATIAL_FRAME - ROTATED_TOKENS_PER_FRAME, :]
        rotated = real_pair(frames[:, :, :, TOKENS_PER_SPATIAL_FRAME - ROTATED_TOKENS_PER_FRAME :, :].reshape(1, 1, SPATIAL_FRAMES * ROTATED_TOKENS_PER_FRAME, 256), self.cross_k_cosine, self.cross_k_sine).reshape(1, 1, SPATIAL_FRAMES, ROTATED_TOKENS_PER_FRAME, 256)
        k = torch.cat((torch.cat((unrotated, rotated), dim=3).reshape(1, 1, SPATIAL_FRAMES * TOKENS_PER_SPATIAL_FRAME, 256), pointers_k), dim=2)
        v = self.heads(self.cross_v_proj(memory))
        current = current + self.cross_out_proj(self.unheads(F.scaled_dot_product_attention(q, k, v, dropout_p=0.0)))

        activated = torch.relu(self.linear1(self.norm3(current)))
        return current + self.linear2(activated)


class FixedOneObjectSteadyMemoryAttention(torch.nn.Module):
    def __init__(self, model: torch.nn.Module):
        super().__init__()
        attention = model.memory_attention
        first_self = attention.layers[0].self_attn
        self_frequency = first_self.compute_cis(end_x=64, end_y=64)
        self.layer0 = FixedRoPELayer(attention.layers[0], self_frequency)
        self.layer1 = FixedRoPELayer(attention.layers[1], self_frequency)
        self.norm = attention.norm

    def forward(
        self,
        current_features: torch.Tensor,
        current_position: torch.Tensor,
        spatial_memory: torch.Tensor,
        spatial_memory_position: torch.Tensor,
        object_pointer_tokens: torch.Tensor,
    ) -> torch.Tensor:
        current = current_features.flatten(2).transpose(1, 2) + 0.1 * current_position.flatten(2).transpose(1, 2)
        memory = torch.cat((spatial_memory, object_pointer_tokens), dim=1)
        pointer_position = torch.zeros_like(object_pointer_tokens)
        memory_position = torch.cat((spatial_memory_position, pointer_position), dim=1)
        current = self.layer0(current, memory, memory_position)
        current = self.layer1(current, memory, memory_position)
        return self.norm(current).transpose(1, 2).reshape(1, 256, 64, 64)


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


def original_output(model: torch.nn.Module, inputs: tuple[torch.Tensor, ...]) -> torch.Tensor:
    features, position, spatial, spatial_position, pointers = inputs
    return model.memory_attention(
        curr=features.flatten(2).permute(2, 0, 1),
        curr_pos=position.flatten(2).permute(2, 0, 1),
        memory=torch.cat((spatial, pointers), dim=1).permute(1, 0, 2),
        memory_pos=torch.cat((spatial_position, torch.zeros_like(pointers)), dim=1).permute(1, 0, 2),
        num_obj_ptr_tokens=POINTER_TOKENS,
        num_spatial_mem=SPATIAL_FRAMES,
    ).permute(1, 2, 0).reshape(1, 256, 64, 64)


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
        "component": "fixed one-object steady-state EdgeTAM memory attention with real-pair RoPE",
        "criteria": "Synthetic component parity only; no image, mask, video, or tracker-quality claim.",
        "upstreamCommit": subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip(),
        "licence": "Apache-2.0",
        "python": sys.version.split()[0], "torch": torch.__version__, "numpy": np.__version__, "coremltools": ct.__version__,
        "computePrecision": "FLOAT32", "computeUnits": "ALL", "minimumDeploymentTarget": "iOS16",
        "inputShapes": [[1, 256, 64, 64], [1, 256, 64, 64], [1, 3584, 64], [1, 3584, 64], [1, 64, 64]],
        "spatialMemoryFrames": SPATIAL_FRAMES, "spatialTokensPerFrame": TOKENS_PER_SPATIAL_FRAME,
        "rotatedSpatialTokensPerFrame": ROTATED_TOKENS_PER_FRAME, "objectPointerTokensExcludedFromRoPE": POINTER_TOKENS,
        "wrapperSHA256": sha256(Path(__file__).resolve()), "checkpointSHA256": sha256(checkpoint),
        "memoryAttentionSourceSHA256": sha256(source / "sam2" / "modeling" / "memory_attention.py"),
        "transformerSourceSHA256": sha256(source / "sam2" / "modeling" / "sam" / "transformer.py"),
    }
    started = time.perf_counter()
    try:
        model = load_model(source, checkpoint)
        wrapper = FixedOneObjectSteadyMemoryAttention(model).eval()
        shapes = ((1, 256, 64, 64), (1, 256, 64, 64), (1, 3584, 64), (1, 3584, 64), (1, 64, 64))
        names = ("current_features", "current_position", "spatial_memory", "spatial_memory_position", "object_pointer_tokens")
        parity = []
        sample = None
        with torch.no_grad():
            for seed, scale in ((7711, 1.0), (2718, 0.5), (3141, 1.5)):
                torch.manual_seed(seed)
                inputs = tuple(torch.randn(shape, dtype=torch.float32) * scale for shape in shapes)
                expected, actual = original_output(model, inputs), wrapper(*inputs)
                delta = (expected - actual).abs()
                parity.append({"seed": seed, "scale": scale, "maxAbsoluteError": float(delta.max()), "meanAbsoluteError": float(delta.mean())})
                sample = inputs
        evidence["pytorchParity"] = parity
        if max(item["maxAbsoluteError"] for item in parity) > 1e-4:
            raise RuntimeError("Wrapped attention did not meet the 1e-4 PyTorch equivalence criterion")
        traced = torch.jit.trace(wrapper, sample, strict=True)
        converted = ct.convert(
            traced,
            inputs=[ct.TensorType(name=name, shape=shape, dtype=np.float32) for name, shape in zip(names, shapes)],
            outputs=[ct.TensorType(name="fused_features")], minimum_deployment_target=ct.target.iOS16,
            compute_units=ct.ComputeUnit.ALL, compute_precision=ct.precision.FLOAT32, convert_to="mlprogram",
        )
        model_path = output / "edgetam_fixed_steady_memory_attention_real_pair.mlpackage"
        converted.save(str(model_path))
        expected = wrapper(*sample).detach().numpy()
        actual = converted.predict({name: value.detach().numpy() for name, value in zip(names, sample)})["fused_features"]
        delta = np.abs(expected - actual)
        evidence.update({"status": "success", "modelPath": model_path.name, "coreMLMaxAbsoluteError": float(delta.max()), "coreMLMeanAbsoluteError": float(delta.mean())})
    except Exception as error:
        evidence.update({"status": "failed", "errorType": type(error).__name__, "error": str(error)})
        (output / "traceback.txt").write_text(traceback.format_exc())
    evidence["elapsedSeconds"] = time.perf_counter() - started
    (output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({key: evidence[key] for key in ("status", "torch", "coremltools", "elapsedSeconds")}))
    return 0 if evidence["status"] == "success" else 1


if __name__ == "__main__":
    raise SystemExit(main())
