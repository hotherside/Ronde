# EdgeTAM research comparator

`edgetam_adapter.py` runs the official EdgeTAM video predictor on private,
lossless AVFoundation frame caches. It is an assisted research comparator and
does not change Ronde's tracker. Mac PyTorch results do not establish iPhone
latency, memory use or accuracy.

## Source and isolated environment

The [official repository](https://github.com/facebookresearch/EdgeTAM) explicitly
licenses its code and checkpoints under Apache-2.0. The inspected checkout is
`7711e012a30a2402c4eaab637bdb00a521302c91`. Its committed
`checkpoints/edgetam.pt` has SHA-256
`ed2d4850b8792c239689b043c47046ec239b6e808a3d9b6ae676c803fd8780df`.
The loaded model contains 13,895,794 parameters.

Keep the checkout, checkpoint, virtual environment, source media, configurations,
frame caches and outputs outside this repository. Use a separate Python 3.12
environment; the BootsTAPIR environment is not modified. The measured setup used:

```sh
/private/edgetam-env/bin/python -m pip install \
  torch==2.14.0 torchvision==0.29.0 numpy==2.5.3 pillow==12.3.0 \
  scipy==1.18.1 timm==1.0.15 hydra-core==1.3.7 iopath==0.1.10 tqdm==4.70.1
```

The adapter imports the external checkout directly. It does not build the CUDA
extension. The upstream constructor normally downloads a redundant pretrained
backbone before loading the complete EdgeTAM checkpoint. The adapter disables
that initial download and retains the official strict full-checkpoint load.
Inference can therefore run with `HF_HUB_OFFLINE=1`.

## Inputs and invocation

Private configurations use `clip_id`, `source_path`, `frame_cache_manifest`,
`avfoundation_frame_manifest`, fixed `crop_xywh`, `crop_type`, `crop_rationale`,
`start_time_seconds`, `end_time_seconds`, and exactly one
`prompts: [{time_seconds, x_px, y_px}]`. Corrections are unsupported. Coordinate
positions belong only in private files, not console logs or repository examples.

```sh
HF_HUB_OFFLINE=1 PYTORCH_ENABLE_MPS_FALLBACK=1 \
  /private/edgetam-env/bin/python \
  Tools/TracerHarness/alternatives/edgetam_adapter.py \
  --config /private/review/edgetam-config.json \
  --edgetam-root /private/models/EdgeTAM \
  --checkpoint /private/models/EdgeTAM/checkpoints/edgetam.pt \
  --output /private/review/edgetam-prediction.json \
  --device mps --max-frames 16
```

Omit `--max-frames` for the complete supplied interval. The limited interval must
include the prompt. The adapter validates consecutive source-frame indices and
actual AVFoundation PTS; it never assigns nominal-FPS timestamps. The prompt
must match a selected source frame within one millisecond. Crops remain fixed
and must be wholly contained in the source cache. Paths resolving inside the
checkout, including symlink targets, are rejected.

An input-loader override supplies the native PNG crop with the official
normalisation directly to the unmodified video-predictor API. Each crop is
resized using Pillow bicubic to the official 1024-square input. This avoids JPEG
recompression and preserves the private source-PTS manifest. There is no moving
crop, super-resolution or source-frame subsampling.

## Frozen output rule and limitations

For the single prompted object, threshold native-crop mask logits at zero and
select the largest 8-connected positive component. Emit its unweighted
pixel-centre centroid, mapped back to normalised top-left source coordinates.
An empty mask abstains. There is no area gate, temporal smoothing, trajectory
fitting, reference-label selection or correction fusion. The seed itself is not
emitted as an observation. Forward and reverse propagation start independently
from the same supplied point.

Raw binary masks, positive-mask area, selected-component area, component count,
mask logits summaries and object-presence scores remain in the private output.
Object presence and nonempty masks do not establish correct golf-ball identity.
The canonical `frames` field contains only derived nonempty-mask centroids.

CUDA hole filling is disabled explicitly. The official stability-based multimask
and prompt-memory binarisation defaults are retained. Model parameters use
float32. CPU input loading and connected-component analysis are explicit; MPS
fallback is enabled, so the run does not demonstrate that every operator uses
the GPU. Timing includes state initialisation, mask propagation and PNG export,
not just a compiled neural-network kernel.

Outputs record source/checkpoint/code hashes, upstream commit, package versions,
assistance, crop and model resolution. Scalar provenance aliases support the
benchmark report allowlist. The two initial native runs received only those
aliases after inference; their actual pre-launch code hash is preserved. Later
runs capture the adapter hash at process start. The mask rule and model settings
were unchanged by that metadata correction.

The corridor inputs may share source crops and point times with BootsTAPIR, but
the input resizing differs: EdgeTAM uses 1024-square input for every crop.
Reviewer-chosen corridors and intervals are assistance. Score every result
against independent source labels before presenting any path as observed ball
flight. Core ML conversion and physical-device validation remain separate work.

The native-midflight configuration originally inherited a BootsTAPIR explanation
of internal 256-to-512 refinement. Its private rationale was corrected to
EdgeTAM's direct 1024-square resize. The original configuration bytes and hash
are retained beside a metadata-correction record. No input pixels, model
settings, masks, timestamps or centroids changed.

## Core ML parity work still required

The inspected upstream scripts are useful starting points, but do not yet prove
parity with this temporal video run:

- The [export script](https://github.com/facebookresearch/EdgeTAM/blob/7711e012a30a2402c4eaab637bdb00a521302c91/coreml/export_to_coreml.py#L329)
  exports image, prompt and mask-decoder components. It does not export the
  temporal memory encoder or memory attention used by the video predictor.
- The [prompt wrapper](https://github.com/facebookresearch/EdgeTAM/blob/7711e012a30a2402c4eaab637bdb00a521302c91/coreml/export_to_coreml.py#L82)
  accepts box and mask arguments but passes `boxes=None` and `masks=None` to the
  underlying prompt encoder. Those advertised inputs need implementation and
  parity checks before use.
- The [image export](https://github.com/facebookresearch/EdgeTAM/blob/7711e012a30a2402c4eaab637bdb00a521302c91/coreml/export_to_coreml.py#L149)
  declares `scale=1/255` and zero bias, while its wrapper directly calls the
  image backbone. This appears to omit the ImageNet mean/std normalisation in
  the [official PyTorch video loader](https://github.com/facebookresearch/EdgeTAM/blob/7711e012a30a2402c4eaab637bdb00a521302c91/sam2/utils/misc.py#L253).
  Validate preprocessing numerically before comparing masks.
- The [mask wrapper](https://github.com/facebookresearch/EdgeTAM/blob/7711e012a30a2402c4eaab637bdb00a521302c91/coreml/export_to_coreml.py#L123)
  converts the multimask tensor flag with `.item()` and branches in Python.
  Since export uses `torch.jit.trace`, this risks freezing the example branch;
  validate both flag values rather than assuming dynamic behaviour survives.
- The [Core ML benchmark](https://github.com/facebookresearch/EdgeTAM/blob/7711e012a30a2402c4eaab637bdb00a521302c91/coreml/benchmark_coreml.py#L108)
  pre-encodes the image outside its timer and measures prompt encoding plus
  mask decoding. Those numbers do not measure full image/video processing,
  temporal memory, source decoding or an end-to-end iPhone tracer.

These are source-review findings and parity risks. No conversion or physical
device test was performed in this comparison.

## Bounded adaptive crop experiment

`edgetam_adaptive_adapter.py` is a separate research adapter. It requires every
upright source pixel and exact AVFoundation PTS for the supplied interval; a
partial corridor cache is rejected. It retains the same model, input resize and
mask-centroid rule. Each direction starts from the same single user point.

A segment uses a fixed 512-square crop. When its observed centroid leaves the
central `[128,384)` square, the next segment recentres on that observation and
reinitialises at the same source frame. A reset happens only if a violating
axis can change its crop origin. This prevents a clamped source-edge axis from
causing resets through small movements on the other axis. The old-crop centroid
remains the canonical observation; the new seed mask and centroid disagreement
are separate transition evidence. Automatic reseeds are counted separately from
the one user point and the two initial directional model prompt applications.

The fixed limits are 32 automatic reseeds across both directions and 240 seconds
of propagation, resets and mask export. Each direction stops at its first empty
or invalid mask. There is no additional motion, area or confidence gate, no
interpolation and no guessed recovery. Source-edge contacts, component counts,
all actual masks and all unprocessed frames remain explicit in private outputs.
These conservative research rules are not an accepted app tracking policy.

The first adaptive run and its source snapshot were retained after a crop-edge
implementation repair. The repair changes only the movable-axis reset guard;
the model, point, interval, 128-pixel margin and resource caps are unchanged.
Synthetic checks cover a clamped top edge with one-pixel central horizontal
drift, legitimate horizontal/vertical recentering and a stationary central point.
No reference labels determine the crop or reset decisions.

The separate gap experiment is opt-in through private configuration field
`source_time_gap_seconds: 0.20`. Omit it or use zero to retain first-empty stopping.
After an observed mask, an empty propagated mask may continue the same state
and crop only while elapsed source time since the last nonempty observation is
at most 0.20 seconds, with a 1e-9 numerical boundary allowance. The deadline is
checked before requesting the next model frame. Source-frame spacing, including
irregular PTS, determines this limit rather than a frame count.

Empty frames emit no point and cannot recenter or reseed. A returning nonempty
mask is a new model observation; no gap coordinates are filled. Initial-prompt,
reseed-mask and invalid-output failures still stop immediately. Private gap
events record all empty timestamps, recovery or termination, crop and segment.
Synthetic tests cover the default policy, exact/reverse/irregular PTS boundaries,
no point or recenter on empty, and missing initial observation. The corrected
first-empty source snapshot and outputs are retained with their original hashes.

Current output `parameters` describes the active empty-mask policy and source-time
limit. The two initial gap outputs inherited the default policy text in that
field, although their dedicated `gapPolicy` and time-limit fields were correct.
Private provenance sidecars record the correction and preserve the original
prediction bytes, executed source snapshot and hashes. No inference or mask
geometry changes are implied by this metadata-only correction.
