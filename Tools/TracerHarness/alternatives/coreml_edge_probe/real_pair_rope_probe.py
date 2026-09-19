#!/usr/bin/env python3
"""Exact real-pair form of EdgeTAM's fixed 64x64 RoPE-v2 query rotation.

Synthetic component probe only. It retains EdgeTAM's original frequency table
as real and imaginary constants, rather than removing rotary position encoding.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
import time

import coremltools as ct
import numpy as np
import torch


def external(path: Path, repo: Path, kind: str) -> Path:
    result = path.expanduser().resolve()
    if result == repo or repo in result.parents:
        raise ValueError(f"{kind} must be outside repository")
    return result


class RealPairRoPEV2(torch.nn.Module):
    def __init__(self, frequency: torch.Tensor):
        super().__init__()
        self.register_buffer("cosine", frequency.real.float())
        self.register_buffer("sine", frequency.imag.float())

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        # value is B, heads, 4096, 256. This is the exact complex product
        # in EdgeTAM apply_rotary_enc_v2, expressed as real even/odd pairs.
        pairs = value.float().reshape(1, 1, 4096, 128, 2)
        cosine = self.cosine.reshape(1, 1, 4096, 128, 1)
        sine = self.sine.reshape(1, 1, 4096, 128, 1)
        even, odd = pairs[..., 0:1], pairs[..., 1:2]
        rotated = torch.cat((even * cosine - odd * sine, even * sine + odd * cosine), dim=-1)
        return rotated.flatten(3).type_as(value)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[4]
    source = external(args.source, repo, "source")
    checkpoint = external(args.checkpoint, repo, "checkpoint")
    output = external(args.output_dir, repo, "output")
    output.mkdir(parents=True, exist_ok=True)
    sys.path.insert(0, str(source))
    from sam2.build_sam import _load_checkpoint
    from hydra import compose, initialize_config_dir
    from hydra.core.global_hydra import GlobalHydra
    from hydra.utils import instantiate
    from omegaconf import OmegaConf
    from sam2.modeling.position_encoding import apply_rotary_enc_v2
    GlobalHydra.instance().clear()
    with initialize_config_dir(config_dir=str(source / "sam2" / "configs"), version_base=None):
        cfg = compose(config_name="edgetam"); OmegaConf.resolve(cfg); model = instantiate(cfg.model, _recursive_=True)
    _load_checkpoint(model, checkpoint)
    original = model.memory_attention.layers[0].cross_attn_image.freqs_cis_q
    wrapper = RealPairRoPEV2(original).eval()
    errors = []
    sample = None
    for seed in (7711, 2718, 3141):
        torch.manual_seed(seed)
        # Real model q projection establishes a representative intermediate scale.
        token = torch.randn(1, 4096, 256)
        query = model.memory_attention.layers[0].cross_attn_image.q_proj(token).reshape(1, 1, 4096, 256)
        expected = apply_rotary_enc_v2(query, original, repeat_freqs=1)
        actual = wrapper(query)
        delta = (expected - actual).abs()
        errors.append({"seed": seed, "inputMeanAbsolute": float(query.abs().mean()), "maxAbsoluteError": float(delta.max()), "meanAbsoluteError": float(delta.mean())})
        sample = query
    if max(item["maxAbsoluteError"] for item in errors) > 1e-4:
        raise RuntimeError("Real-pair RoPE did not meet the 1e-4 PyTorch equivalence criterion")
    traced = torch.jit.trace(wrapper, sample, strict=True)
    started = time.perf_counter()
    converted = ct.convert(traced, inputs=[ct.TensorType(name="query", shape=(1, 1, 4096, 256), dtype=np.float32)], outputs=[ct.TensorType(name="rotated")], minimum_deployment_target=ct.target.iOS16, compute_units=ct.ComputeUnit.ALL, compute_precision=ct.precision.FLOAT32, convert_to="mlprogram")
    converted.save(str(output / "edgetam_real_pair_rope_v2.mlpackage"))
    coreml = converted.predict({"query": sample.detach().numpy()})["rotated"]
    parity = np.abs(wrapper(sample).detach().numpy() - coreml)
    evidence = {"component":"fixed 64x64 EdgeTAM RoPE-v2 query rotation", "upstreamCommit":"7711e012a30a2402c4eaab637bdb00a521302c91", "dtype":"float32", "computePrecision":"FLOAT32", "inputShape":[1,1,4096,256], "torch":torch.__version__, "coremltools":ct.__version__, "numpy":np.__version__, "wrapperSHA256":sha256(Path(__file__).resolve()), "checkpointSHA256":sha256(checkpoint), "ropeSourceSHA256":sha256(source / "sam2" / "modeling" / "position_encoding.py"), "seeds":errors, "coreMLMaxAbsoluteError":float(parity.max()), "coreMLMeanAbsoluteError":float(parity.mean()), "elapsedConversionSeconds":time.perf_counter()-started, "criteria":"Synthetic operator parity only; no full memory-attention, video, or tracker-quality claim."}
    (output / "evidence.json").write_text(json.dumps(evidence, indent=2)+"\n")
    print(json.dumps({"maxPyTorchError":max(item["maxAbsoluteError"] for item in errors), "coreMLMaxAbsoluteError":float(parity.max())}))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
