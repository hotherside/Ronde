# Prompted tracker comparison

`bootstapir_adapter.py` runs Google's official offline BootsTAPIR v2 on local
source frames. This is a research comparator, not part of Ronde's automatic
tracker. Mac inference does not establish iPhone performance or tracer accuracy.
Keep all user-specific configurations, source media, cached frames, predictions,
models and downloaded third-party code outside this repository.
The adapter rejects source media, configuration, checkpoints, output, nested
manifests and cached-frame paths that resolve inside the checkout, including
symlink targets. Console progress reports dimensions and counts, not positions.

## Reproducible setup

Use an isolated Python 3.12 virtual environment. Do not install packages into the
bundled Codex runtime. Install `requirements.txt` into that environment. The
September 2026 comparison used PyTorch MPS on a Mac; CPU is also an explicit
option. MPS fallback may run an unsupported operator on CPU when
`PYTORCH_ENABLE_MPS_FALLBACK=1` is set, so this flag is not evidence that every
operator uses the GPU.

Clone [official TAPNet](https://github.com/google-deepmind/tapnet) outside the
repository and select commit `730cda1c730877cfedbe01bf87fb1cadb78a565d`. Obtain the
[official BootsTAPIR v2 checkpoint](https://storage.googleapis.com/dm-tapnet/bootstap/bootstapir_checkpoint_v2.pt)
separately. Its verified SHA-256 is
`8493c7a69e02c85b9382fbb3c7b8b539b36bc08ede744b9e99feb739a0129f4b`.
The upstream README explicitly places both the code and linked model checkpoints
under Apache-2.0. The adapter does not download or execute remote instructions.

```sh
PYTORCH_ENABLE_MPS_FALLBACK=1 /private/model-env/bin/python \
  Tools/TracerHarness/alternatives/bootstapir_adapter.py \
  --tapnet-root /private/models/tapnet \
  --checkpoint /private/models/bootstapir_checkpoint_v2.pt \
  --config /private/review/model-config.json \
  --output /private/review/prediction.json \
  --device mps
```

Use `--max-frames 16` for a bounded runtime check. The selected interval must
contain the prompt, including when a maximum frame count is used.

## Private configuration

Configuration fields:

| Field | Meaning |
| --- | --- |
| `clip_id`, `source_path` | Scorer clip identity and local original |
| `start_time_seconds`, `end_time_seconds` | Supplied source interval; all consecutive frames retained |
| `crop_xywh` | Fixed integer crop in upright source pixels |
| `crop_type`, `crop_rationale` | Explicit assistance provenance; use `oracle_fixed_corridor` when the clip's path informed the crop |
| `model_input_size` | Model input `[width,height]`, each at least 256 and divisible by eight |
| `prompts` | Exactly one `{time_seconds,x_px,y_px}` source-coordinate prompt |
| `avfoundation_frame_manifest` | Source frame-times JSON for strict PTS comparison |
| `frame_cache_manifest` | Optional native PNG manifest from `../Reference/ExtractReferenceFrames.swift` |
| `rotation_ccw_degrees` | Explicit PyAV rotation, default zero; AVFoundation caches are already upright |

The AVFoundation cache should use a single fixed inspection-crop anchor. The
adapter can extract a smaller fixed rectangle from those square images. Each
requested rectangle must be fully contained in its source cache frame. Cache
timestamps and frame indices are retained exactly. Image resizing uses bilinear
sampling and is recorded; no super-resolution or trajectory-based moving crop
is applied. The model's own initial matching resolution is 256×256, followed by
the upstream multiresolution refinement, even for larger adapter inputs.

PyAV and AVFoundation can interpret an edited MOV timeline differently. For one
reviewed original they returned different frame counts and initial PTS. Never
repair that by assigning AVFoundation times to PyAV frame indices. Use the
AVFoundation cache when source timings disagree. The strict manifest check
rejects a disagreement greater than one microsecond.

## Output and limits

The root output conforms to the harness prediction schema: `mode: assisted`,
`promptCount: 1`, `correctionCount: 0`, normalised top-left coordinates and source
PTS. `frames` contains only points passing the upstream visibility rule:
`(1-sigmoid(occlusion)) * (1-sigmoid(expected_dist)) > 0.5`.
Raw predictions, including rejected points, remain in `samples`/`tracks` with
visibility, scores and logits. Scores are not calibrated probabilities that a
golf-ball position is correct. Values are mapped back using x/width and y/height;
no clipping, smoothing, interpolation or curve fitting alters them.

The adapter records source and checkpoint hashes, upstream commit, crop,
resampling, actual snapped prompt frame, package versions and measured timings.
Prompts may snap only to a source frame within 25 ms. The source frame interval
must remain consecutive. Offline inference can use future frames. It does not
fuse additional correction points or train on the reviewed clips.

Model visibility is an output to score, not permission to present a path as
observed ball flight. Evaluate against independently reviewed source labels.
The test has not converted this model to Core ML or measured phone memory,
thermals, latency, or accuracy. Export and physical-device profiling remain
separate work.

## Native seeded bright-object comparator

`native_point_tracker.py` is a lightweight Pillow comparator for a private
AVFoundation full-frame PNG cache. It accepts one declared first-visible,
normalised source point and exact source PTS, then searches a camera-translation
compensated moving ROI for bright, temporally changed image peaks. Its shared
parameters are in source and cannot be overridden by a clip configuration.
It rejects cropped caches, label/candidate-pool inputs, paths inside this
repository and seed timestamps that do not occur in the AVFoundation manifest.

```sh
/private/model-env/bin/python Tools/TracerHarness/alternatives/native_point_tracker.py \
  --config /private/review/native-point-config.json \
  --output /private/review/native-point-prediction.json
```

The output contains only observed local candidates at manifest PTS, a private
candidate pool and per-frame outcome diagnostics. It omits the supplied seed
from `frames`; after consecutive local-observation misses it emits no estimated
continuation. This is an assisted research comparator, not app integration or
an accuracy claim.
