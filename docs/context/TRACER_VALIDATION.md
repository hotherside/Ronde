# Shot Tracer Validation Ledger

**Reviewed:** 30 August 2026

This ledger separates deterministic source and Simulator checks from footage accuracy and physical-device performance. It contains no private media. Validation clips remain in an owner-controlled external directory and must be consented for this use.

## Release matrix

The release-quality matrix requires 20 to 30 labelled clips across the following dimensions. A single clip may cover several cells, but positives and negatives must be reported separately.

| Dimension | Required coverage |
| --- | --- |
| Presentation rate | 25, 30, 50, 60, 120 and 240 fps, including variable-frame-rate phone media where available |
| Orientation | Portrait and landscape |
| Club | Driver, iron and wedge |
| Surface | Range mat and grass |
| Background | Clear sky, trees, netting and range clutter |
| Light | Bright, overcast, dusk or night range |
| Positive | Visible target-golfer impact followed by a golf-ball launch |
| Negative | Practice swing, waggle, impact-like noise, neighbouring golfer and unrelated visible ball |

## Per-clip evidence

Record the following without copying the source video into Git:

- opaque clip ID and consent status;
- source dimensions, orientation, duration and presentation-rate summary;
- labelled impact time and expected positive or negative result;
- acquisition result, observed point count and observed time span;
- estimate provenance and whether a tracer was displayed or withheld;
- analysis wall-clock duration, analysed sample count, full-search frames and tile inference count;
- false-tracer result for negatives;
- device model, OS version and thermal state for physical-device runs;
- detector weight hash and source revision.

## Current evidence

| Evidence | Result | Boundary |
| --- | --- | --- |
| Synthetic timebase tests | Passed at 25, 30, 50, 60, 120 and 240 fps on iPhone 17 Pro iOS 26.5 Simulator | Proves selector and sampling invariance only, not detector accuracy on decoded footage |
| Three supplied private positive clips | Exact production tracker passed two 4K landscape daylight clips and one 4K portrait night-range clip on macOS and iPhone 17 Pro iOS 26.0 Simulator | Positive regression evidence only; clips are not retained in the repository and do not replace a held-out matrix |
| Representative held-out matrix | Not supplied | Blocks accuracy, false-tracer and cross-source reliability claims |
| Physical iPhone performance | Not run | Blocks latency, memory, battery and thermal claims |
| Golf-specific fine-tune | Not run | No licensed, consented golf training set is present; the official upstream repository documents evaluation but its training section remains `TBA` |
| Distance and apex-height ground truth | Not supplied | Blocks numerical carry and height outputs |

## 30 August positive regression

Three owner-supplied originals remained outside Git and were temporarily installed only into a disposable signed test bundle. The exact Swift decoder, packaged Core ML model, acquisition guard and selector passed all three on iPhone 17 Pro iOS 26.0 Simulator. After the memory correction, the single external-matrix test passed again with zero skips or failures in 1,397.075 seconds on Simulator without iPhone Neural Engine acceleration; this is regression evidence, not a device-latency benchmark.

| Opaque clip | Source | Impact anchor | Final observed result | Local diagnostic cost |
| --- | --- | --- | --- | --- |
| Landscape A | 3840 x 2160 H.264, about 30 fps, 6.315 s | 1.6320 s audio | 7 points, confidence 0.307; launch around `(0.532, 0.273)` | 30 decoded, 29 sampled, 18 model windows, 975 tiles |
| Landscape B | 3840 x 2160 HEVC, nominal 30 fps, 7.725 s | 0.8747 s audio | 86 points, confidence 0.828; launch around `(0.754, 0.199)` | 116 decoded, 115 sampled, 104 model windows, 3,217 tiles |
| Portrait C | 2160 x 3840 H.264, about 30 fps, 6.618 s | 1.6747 s audio | 82 points, confidence 0.712; launch around `(0.563, 0.351)` after trimming pre-ball club/body motion | 115 decoded, 114 sampled, 101 model windows, 4,985 tiles |

The incident was a false-acquisition failure, not an overlay coordinate conversion. The former search narrowed around the first high-confidence coherent moving peak, which could be foliage, compression detail, club or body motion and permanently exclude the later-visible ball. Acquisition now lets full-frame track hypotheses compete through the post-impact launch window, requires eight linked detections before narrowing to a local ROI or displaying a later trimmed path, and trims an early detector hand-off before labelling points observed. If no defensible path remains, the existing no-tracer state still wins.

### Memory-pressure regression

The same production-code diagnostic exposed a separate termination risk: a 5.3 MB Core ML input tensor was allocated once per tile rather than once per model window. Landscape B therefore allocated 3,217 large tensors and reached a measured 19.19 GB peak process footprint. The implementation now reuses one input tensor across every tile in a three-frame window and encloses each synchronous prediction in its own autorelease pool. The observed tracks and confidence values were unchanged.

| Opaque clip | Model windows / tiles | Peak footprint after correction | Maximum resident memory after correction |
| --- | ---: | ---: | ---: |
| Landscape A | 18 / 975 | 235 MB | 578 MB |
| Landscape B | 104 / 3,217 | 699 MB | 1.04 GB |
| Portrait C | 101 / 4,985 | 678 MB | 1.02 GB |

These are macOS diagnostic measurements against the exact Swift tracker, not a physical-iPhone benchmark. A fresh hardware run must still confirm that One Shot completes without an OS memory termination and capture device model, OS, runtime, thermal state and peak memory.

## Acceptance thresholds

Thresholds must be set only after the labelled matrix exists. Report acquisition recall on positives, false-tracer rate on negatives and target-golfer association errors separately. A lower frame rate may reduce evidence quality, but must never change eligibility rules or cause timestamps to be inferred from nominal FPS.
