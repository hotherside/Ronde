# EdgeTAM Core ML component probes

This is a fixed-shape, synthetic component-conversion probe. It tests the real
one-object steady-state temporal attention module only: seven full 512-token
memory frames and sixteen object pointers split into 64 tokens. It does not
read media, labels, masks or benchmark results, and it makes no tracking-quality
claim.

Use a private converter environment with EdgeTAM available only through a
read-only `PYTHONPATH`; place all artefacts outside this repository.

```sh
PYTHONPATH=/private/edgetam \
  /private/conversion-venv/bin/python \
  Tools/TracerHarness/alternatives/coreml_edge_probe/steady_state_memory_attention_probe.py \
  --source /private/edgetam \
  --checkpoint /private/edgetam/checkpoints/edgetam.pt \
  --output-dir /private/edge-coreml-probe/output
```

The probe writes `evidence.json` and, on failure, `traceback.txt`. It requests
an iOS 16 ML Program with Core ML float32 conversion and `ComputeUnit.ALL`.

## Current gate

The direct fixed-shape memory-attention conversion was attempted with Core ML
Tools 9.0, NumPy 1.26.4 and float32 conversion. It reaches EdgeTAM's complex
RoPE frequency cast and stops in the Core ML Torch frontend with `KeyError: 9`.
The recorded direct attempt used Torch 2.14.0, which is outside the Core ML
Tools 9 tested Torch range. A repeat with supported Torch 2.7.0 reached the
same cast and stopped with the same error. This is a direct memory-attention
conversion blocker, not evidence about a Core ML video pipeline or tracking
quality.

The direct module remains blocked, but a separate fixed-state wrapper that
retains both original attention layers and re-expresses only their complex
RoPE products has converted in float32. It uses seven 512-token spatial memory
blocks and 64 unrotated pointer tokens. Its synthetic PyTorch and Core ML
parity is recorded externally. It does not include memory encoding, video
state/update policy, masks, image encoding, or tracking behaviour.

Any future RoPE re-expression must preserve the original mathematical
operation and establish separate PyTorch and Core ML component parity before
it is used in a larger wrapper. The isolated fixed-shape RoPE-v2 query rotation
also met that narrower operator-level criterion.

`flexible_memory_attention_probe.py` extends the reviewed real-pair implementation
to variable history without padding: 1–7 full spatial memories and 1–16 object
pointers. The caller must enforce 512-token spatial blocks, four-token pointers,
matching memory/position lengths and zero pointer-position tokens. The initial
conditioning frame bypasses this attention through the original upstream logic.
It compares original, traced and Core ML outputs at several history lengths and
records a full package-tree hash. This is a component conversion, not video parity.

`sam_heads_probe.py` tests the supplied positive-point case. Its positive-label
Torch trace freezes boolean-index cardinality and cannot safely execute the
no-point case. `sam_heads_no_point_probe.py` calls the original no-point method
and exports that mode separately. Keep low-resolution 256-pixel masks for the
source-output resize and high-resolution 1024-pixel masks for memory encoding;
do not substitute one resampling route for the other. Both exports retain the
IoU outputs, object pointer and object score needed by the video state.

`coreml_video_component_parity.py` is a diagnostic bridge into the original
Python video predictor. It must preserve source PTS, preprocessing, positional
encoding, conditioning and the original bfloat16 stored-memory roundtrip.
Component success does not establish combined video parity, a Swift port,
phone latency or golf-ball accuracy. Keep incomplete runs and failed gates
separate from completed numerical comparisons.

## Image and memory encoder components

`image_memory_encoder_probe.py` exports the pinned EdgeTAM image encoder and
memory encoder/Perceiver as separate synthetic Core ML components. Keep the
source checkout, checkpoint, conversion environment and output directory
outside the repository:

```sh
PYTHONPATH=/private/edgetam \
  /private/conversion-venv/bin/python \
  Tools/TracerHarness/alternatives/coreml_edge_probe/image_memory_encoder_probe.py \
  --source /private/edgetam \
  --checkpoint /private/edgetam/checkpoints/edgetam.pt \
  --output-dir /private/edge-coreml-probe/output-image-memory \
  --component all
```

The image input is already normalised by the caller with mean
`(0.485, 0.456, 0.406)` and standard deviation `(0.229, 0.224, 0.225)`.
The wrapper passes that tensor directly to `forward_image`; it does not apply
normalisation a second time or add `no_mem_embed`. It returns the raw projected
features used by the video path: `[1, 256, 64, 64]`, `[1, 32, 256, 256]`, and
`[1, 64, 128, 128]`.

The memory component takes pixel features `[1, 256, 64, 64]`, mask logits
`[1, 1, 1024, 1024]`, object-score logits `[1, 1]`, and a runtime `mask_mode`
scalar. `mask_mode=0` selects sigmoid tracking masks and `mask_mode=1` selects
binarised point masks. Both packages retain the runtime selector and the
official positive/negative object-score gate before the 512-token, 64-channel
Perceiver output. The caller remains responsible for any later bfloat16 memory
feature cast.

With `--component all`, evidence is written independently to
`image/evidence.json` and `memory/evidence.json` below the private output
directory, with one ML Package per component or mask mode. The evidence records
Torch-to-wrapper and Core ML-to-wrapper errors, output shapes, upstream revision,
checkpoint hash and conversion environment. Inputs are deterministic synthetic
tensors only; these probes establish component numerical parity and make no
video, device or tracking-quality claim.
