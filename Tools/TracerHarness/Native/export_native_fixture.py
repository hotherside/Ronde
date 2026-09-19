#!/usr/bin/env python3
"""Export private raw-RGB/constant fixtures for the native Swift parity runner.

Frame selection, crop, point and source timestamps come from the frozen fixed-crop
comparison configuration. No reference labels or detector positions are read.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

REPO = Path(__file__).resolve().parents[3]


def external(path):
    path = Path(path).expanduser().resolve()
    if path == REPO or REPO in path.parents:
        raise ValueError("Private fixture inputs and outputs must remain outside Git")
    return path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--checkpoint", type=Path, required=True)
    p.add_argument("--config", type=Path, required=True)
    p.add_argument("--output-dir", type=Path, required=True)
    p.add_argument("--max-frames", type=int, default=32)
    args = p.parse_args()
    source, checkpoint, config_path, out = map(external, (args.source, args.checkpoint, args.config, args.output_dir))
    if out.exists():
        raise FileExistsError("Refusing to overwrite an existing native fixture")
    config = json.loads(config_path.read_text())
    cache_path = external(config["frame_cache_manifest"])
    av_path = external(config["avfoundation_frame_manifest"])
    cache, av = json.loads(cache_path.read_text()), json.loads(av_path.read_text())
    crop = config["crop_xywh"]
    if len(crop) != 4 or any(type(v) is not int for v in crop) or min(crop) < 0 or min(crop[2:]) <= 0:
        raise ValueError("Invalid crop")
    if args.max_frames < 2 or len(config["prompts"]) != 1:
        raise ValueError("A single point and at least two frames are required")
    frames = [f for f in cache["frames"] if config["start_time_seconds"] <= f["timestamp"] <= config["end_time_seconds"]][:args.max_frames]
    if not frames:
        raise ValueError("No selected source frames")
    for index, frame in enumerate(frames):
        if abs(av["frameTimes"][frame["frameIndex"]] - frame["timestamp"]) > 1e-9:
            raise ValueError("Source timestamp mismatch")
        if index and frame["frameIndex"] != frames[index - 1]["frameIndex"] + 1:
            raise ValueError("Nonconsecutive source cache")
    point = config["prompts"][0]
    seed = min(range(len(frames)), key=lambda i: abs(frames[i]["timestamp"] - point["time_seconds"]))
    if abs(frames[seed]["timestamp"] - point["time_seconds"]) > .001:
        raise ValueError("Point timestamp is not among selected source frames")
    sys.path.insert(0, str(source))
    sys.path.insert(0, str(REPO / "Tools/TracerHarness/alternatives/coreml_edge_probe"))
    import numpy as np
    from PIL import Image
    import torch
    from sam_heads_probe import load_model

    model = load_model(source, checkpoint)
    constants = {
        "noMemoryEmbedding": model.no_mem_embed.detach().reshape(-1).tolist(),
        "memoryTemporalEmbeddings": model.maskmem_tpos_enc.detach().reshape(7, 64).tolist(),
    }
    out.mkdir(parents=True)
    (out / "constants.json").write_text(json.dumps(constants) + "\n")
    with torch.no_grad():
        position = model.image_encoder.neck.position_encoding(torch.zeros(1, 256, 64, 64))
        position.numpy().astype("<f4").tofile(out / "expected-position.f32")
    rows = []
    for index, frame in enumerate(frames):
        with Image.open(external(cache_path.parent / frame["file"])) as image:
            left, top = crop[0] - frame["cropX"], crop[1] - frame["cropY"]
            if min(left, top) < 0 or left + crop[2] > image.width or top + crop[3] > image.height:
                raise ValueError("Crop lies outside cached image")
            rgb = image.convert("RGB").crop((left, top, left + crop[2], top + crop[3]))
            path = out / f"frame-{index:03d}.rgb"
            path.write_bytes(rgb.tobytes())
            if index == seed:
                image1024 = np.asarray(rgb.resize((1024, 1024), Image.Resampling.BICUBIC)).copy()
                tensor = torch.from_numpy(image1024).permute(2, 0, 1).float() / 255.0
                tensor = (tensor - torch.tensor([.485, .456, .406])[:, None, None]) / torch.tensor([.229, .224, .225])[:, None, None]
                tensor.numpy().astype("<f4").tofile(out / "expected-seed-image.f32")
        rows.append({"sourceFrameIndex": frame["frameIndex"], "timestamp": frame["timestamp"], "rgb": path.name, "rgbSHA256": digest(path)})
    manifest = {
        "schemaVersion": 1, "sourceHash": "sha256:" + digest(external(config["source_path"])),
        "sourceWidth": cache["width"], "sourceHeight": cache["height"], "crop": crop,
        "seedIndex": seed,
        "pointModel": [(point["x_px"] - crop[0]) / crop[2] * 1024, (point["y_px"] - crop[1]) / crop[3] * 1024],
        "constants": "constants.json", "frames": rows,
        "provenance": {"generatorSHA256": digest(Path(__file__)), "configurationSHA256": digest(config_path),
                       "checkpointSHA256": digest(checkpoint), "cacheManifestSHA256": digest(cache_path),
                       "avManifestSHA256": digest(av_path),
                       "upstreamRevision": subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip(),
                       "torch": torch.__version__, "numpy": np.__version__},
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"frames": len(rows), "seedIndex": seed, "fixture": str(out)}))


if __name__ == "__main__":
    main()
