# Shot Tracer Validation Ledger

**Reviewed:** 19 September 2026

This ledger separates deterministic source and Simulator checks from footage accuracy and physical-device performance. It contains no private media. Validation clips remain in an owner-controlled external directory and must be consented for this use.

## 19 September owner crash report and flow revision

The owner reported tracking stalled at 10% followed by an app crash. Code locates this progress state immediately before the first model inference completes; no crash/jetsam log was available and the device was disconnected. Memory pressure is unconfirmed. The local mitigation releases cached upright RGB before inference, adds cancellation checks around Core ML calls and switches physical iOS EdgeTAM to CPU/Neural Engine. This is a validation candidate, not proof of a resolved crash.

[ADR 0018](decisions/0018-clip-first-tracing-and-correction.md) changes the entry flow to automatic observed seed discovery, with point selection and drawn paths as correction. Import/bookmark/trace intervals and provenance were updated. The app suite passes 141 checks with two skips on Simulator. The earlier two-clip numbers below remain supplied-point Mac evidence; they do not measure this new automatic seed selector, compute policy or phone behaviour. Physical execution, scoring, cancellation and exported-video inspection remain the next gate.

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
- automatic, point-assisted or manual provenance, supplied point/interval, impact/start/loss boundaries and whether a tracer was displayed or withheld; the product does not present estimated landing or numerical carry;
- traced-export duration, frame count and presentation cadence when an export is inspected;
- analysis wall-clock duration, analysed sample count, full-search frames and tile inference count;
- false-tracer result for negatives;
- device model, OS version and thermal state for physical-device runs;
- detector weight hash and source revision.

## 19 September source-timed development benchmark

**Source:** local, uncommitted `codex/tracer-evidence-benchmark` from `7a6bd012484419faf3f23011cee7f4ae12b4a6b3`. The exact-source macOS harness uses the packaged WASB model, default production acquisition/association policy and a supplied impact time. This is assisted timing, with no point or crop prompts in the baseline. Automatic impact discovery is outside this comparison.

Two owner-supplied originals remain outside Git. The daylight source is 3840 × 2160 HEVC, 7.725 seconds; the night source is 2160 × 3840 H.264, 6.618 seconds. Reference crops were decoded at native scale with AVFoundation source presentation timestamps. One source has different initial frame counts/timestamps through FFmpeg/PyAV, so frame-index or nominal-FPS substitution would invalidate the comparison.

The reference contains 113 daylight and 103 night visible positions with `agent-reviewed` provenance, not human-verified ground truth. Contrast-based centre proposals were inspected and launch/late positions corrected against source crops independently of tracker output. Blur uncertainty is recorded. Uncertain, pre-launch and occluded frames have no inferred ball coordinate; late flight is not claimed complete. Thresholds of 4 and 12 source pixels are exploratory diagnostics, not accepted release requirements.

The table uses a 1 ms source-PTS matching tolerance and an absolute 12-pixel localisation threshold. Missing predictions count as misses in the denominator; p95 covers timestamp-matched visible positions only.

| Experiment | Daylight correct / 113 visible | Night correct / 103 visible | Interpretation |
| --- | ---: | ---: | --- |
| Default WASB with supplied impact | 87 (77.0%) | 80 (77.7%) | 88/84 timestamp matches; one/four wrong retained points; p95 error 2.12/3.35 px, maximum 47/1,225 px |
| Three heatmap peaks per tile | 0 | 0 | Eight-point wrong-object tracks on each clip; rejected, default remains one peak |
| BootsTAPIR, full-flight corridor | 1 | 1 | Supplied point, interval and fixed crop; only seed localises correctly; no adoption |
| One-point replay of baseline candidates | 88 (77.9%) | 84 (81.6%) | p95 2.40/3.31 px; zero/two wrong matched points; night maximum 573 px; outside app |
| First-visible-point replay | 0 | 0 | Four/three wrong selected positions; unchanged association settings; no adoption |
| First-visible native-pixel bright-object tracker | 2 (1.8%) | 0 | Daylight terminates early; night returns 100 wrong positions; no adoption |
| EdgeTAM, full-flight corridor | 1 | 100 (97.1%) | One supplied point plus fixed inspected corridor and interval; night p95 3.26 px, no wrong points at 12 px; not automatic acquisition |
| EdgeTAM, full interval with fixed prompt-centred 512 crop | 16 (14.2%) | 91 (88.3%) | Same points/intervals and frozen model rules; all emitted positions within 12 px, but missing coverage remains |
| EdgeTAM, model-driven moving 512 crop, first empty stops | 93 (82.3%) | 102 (99.0%) | Same point/interval policy; eight/seven automatic resets; night covers all visible labels but launch-streak centre exceeds 12 px |
| EdgeTAM, same moving crop, 0.20-second dropout bound | 104 (92.0%) | 102 (99.0%) | Eleven additional correct daylight observations; nine visible daylight frames still missing; night outputs unchanged |

The default baseline also scores 87/113 and 80/103 at 4 pixels. Its raw pools contain 89/113 and 85/103 candidate hits at 12 pixels, evaluated across every candidate at a matched source time. A correct candidate can be available without being selected. This recall is conditional on the baseline's ROI searches and cadence; it is not independent full-frame detector recall.

Independent source inspection confirmed the five baseline errors: empty sky in daylight, then shoe, trousers, background light and cap in the early night track. The one-point replay uses frozen shared forward/backward motion gates and emits only unchanged raw detections, never the supplied seed or an interpolated point. It removes those original errors, but attaches two different early night cap points. No threshold tuning or post-score removal hides those failures. The next perception work needs both trustworthy launch identity/start boundaries and improved candidate coverage.

A subsequent first-visible-point experiment kept that association algorithm unchanged and selected the earliest reviewed visible reference point deterministically. It failed on both clips. Night's first near-ball candidate arrives 0.267 seconds after that seed, beyond the frozen 0.20-second gap; daylight has a near-ball candidate at 0.167 seconds but chooses ground texture. The daylight input adds exactly one empty row at the real, previously unanalysed seed PTS because the pool starts later; it does not add a detector observation. All original candidates are preserved. Moving the prompt earlier is therefore not a demonstrated fix.

A separate lightweight comparator used full native AVFoundation frames, one first-visible point, a moving search area, local bright contrast, temporal difference and coarse translation compensation. It did not consume the WASB pool or other labels. Shared parameters were frozen before scoring. It obtains two daylight hits at 12 pixels, zero at 4 pixels, then terminates; its 100 night outputs have median error 1,003 pixels and inspected samples select range-floor detail and distance markers. Every estimated camera translation is zero on these runs, so this does not validate registration. The failed comparator remains external to the product; neither speed nor a dense path justifies adoption.

The official BootsTAPIR v2 offline checkpoint ran locally in isolated PyTorch/MPS with future frames and declared assistance. Broad corridor runs took about 80.7/44.2 seconds of model inference on the Mac. A separate night native-crop mid-flight experiment obtained 44/78 correct positions at 12 pixels within its shorter interval (35/78 at 4 pixels), then drifted. Crop resolution and temporal interval changed together, so this is not an isolated resolution ablation. No Core ML conversion, phone speed claim or blanket conclusion about all prompted trackers follows.

The official EdgeTAM checkpoint improves the night corridor result to 100/103 correct at 12 pixels and 99/103 at 4 pixels, with three final visible frames missing. Root inspection of launch, mid-flight and late source crops supports ball identity in sampled outputs; the model also abstains in the inspected later cap-occluded frames. Daylight produces only the prompted position (1/113). A separate 512 × 512 native-source night crop reaches 78/78 within its selected middle interval at 12 pixels, 76/78 at 4 pixels. These runs use one supplied clear-air point, a fixed supplied crop and future frames; they do not prove one-tap or fully automatic performance. The full corridor propagation and mask export take approximately 53.95/38.67 seconds on Mac MPS, and the shorter night crop 21.01 seconds. All 361 source-frame mask/centroid mappings were independently reconstructed from retained masks.

A controlled follow-on held each full interval and supplied point constant and used a deterministic fixed 512 × 512 source crop centred on that point. It reaches 16/113 daylight and 91/103 night at 12 pixels (15/113 and 85/103 at 4 pixels). No emitted point exceeds 12 pixels on reviewed visible frames; most daylight positions remain missing. Narrow crops can also exclude flight outside their field of view. The two runs total 98.01 seconds of Mac propagation/export. The containment audit finds only 15/113 daylight and 90/103 night reference centres inside those fixed squares; all in-crop centres are within 12 pixels, with one additional near-boundary hit per clip. This is a field-of-view limitation, not evidence that EdgeTAM cannot track the remaining daylight ball at native detail. A prediction-driven moving crop is a justified next experiment, with no label-derived crop path. The label-selected union of WASB and the best EdgeTAM output provides diagnostic upper bounds of 95/113 daylight and 100/103 night; it is not an implemented ensemble.

The daylight moving-crop experiment reads complete native source frames and recentres only from previous model observations. Its initial implementation reaches 47 correct positions before exhausting 32 resets. Raw diagnostics identify 31 unnecessary resets caused by an image-edge clamp combined with small movement on the other axis. A narrow repair requires an out-of-margin axis to be movable before resetting; the original run is preserved. The corrected run retains all model, mask, margin and budget settings and reaches 93/113 at 12 pixels, 92/113 at 4 pixels, with median error 0.81 px, p95 1.50 px and maximum 6.51 px. It uses eight automatic model-derived point resets, takes 50.68 seconds on Mac MPS and stops on the first empty mask in each direction. No user correction, reference-derived crop, inserted seed or interpolated position is emitted. Twenty reviewed visible positions remain missing: the first visible frame and 19 later positions across 4.037–4.737 seconds, excluding uncertain gaps. Both first-empty reference centres remain inside the active crop, so the remaining stop events concern perception/termination rather than field-of-view loss.

The same frozen moving-crop policy on night emits 104 positions: all 103 reviewed visible frames and one uncertain frame. It reaches 102/103 at 12 pixels and 95/103 at 4 pixels, with median 0.95 px, p95 5.08 px and maximum 48.49 px. The strict outlier lies on the long launch blur; it is accepted by the reference's declared uncertainty, but the absolute error is retained. The three final visible positions missed by the supplied corridor are recovered. There are no predictions on eight explicitly absent frames. Seven automatic resets take 86.06 seconds of Mac propagation/export. Root sampled launch and late native source crops, without relabelling to improve scores.

One bounded dropout experiment per clip changes only empty-mask termination: after an observation, continue the same predictor state in the same crop for at most 0.20 seconds of actual source time. Empty frames receive no coordinates, crop movement or seed. A returned mask supplies its actual centroid; initial/reseed-empty and resource stops remain unchanged. Daylight improves to 104/113 at 12 pixels and 103/113 at 4 pixels, with median 0.82 px, p95 1.47 px and maximum 6.51 px; all 104 emitted points match visible labels, leaving nine misses. Four recoveries and nine resets take 65.54 seconds. Night adds no positions and retains exactly the control's canonical points; it processes six empty frames before stopping, with seven resets in 54.96 seconds. Concurrent Mac timings are diagnostic, not a speed comparison. All 95 daylight and 105 night processed control masks are byte-identical in their corresponding gap runs. Nine synthetic checks cover source-time boundaries, reverse/irregular PTS, no points or crop changes on empty masks, and image-edge resets. Frozen prediction files retain a stale inherited default-policy description alongside their correct explicit active gap policy; provenance sidecars document this, and current serialisation is corrected without rerunning inference.

EdgeTAM code and weights are Apache-2.0 at upstream `7711e012a30a2402c4eaab637bdb00a521302c91`; the checkpoint SHA-256 is `ed2d4850b8792c239689b043c47046ec239b6e808a3d9b6ae676c803fd8780df`. Its checked-out Core ML exporter covers image encoder, prompt encoder and mask decoder only. The temporal memory/attention, preprocessing and state requirements are addressed by the separate conversion/native checks below. The upstream static benchmark omits per-frame image encoding and temporal propagation from its timed loop. Neither that script nor the published phone benchmark establishes Ronde phone latency or parity.

Root inspection of the nine remaining daylight misses finds every reference centre inside its processed crop. Every frame has a negative object-presence score and the model's absent-object mask value. The first is the initial ball over grass; the other eight are faint late-flight positions. This narrows the next model/correction question to presence/localisation rather than unprocessed frames or crop coverage. No threshold was weakened and no reference label changed.

The baseline performs 104/102 model windows and 3,362/5,070 tile inferences. Public code and weights were downloaded locally; private footage was not uploaded. The packaged weight SHA-256 is `508eec685ff6f8d20667d739ed0f3038a20d37de4121056a1b4f537c5564f8ee`. Future manifests hash the complete model tree; historical run manifests explicitly label the old specification-only hash and separately retain verified bundle/weight hashes.

A direct fixed-state memory-attention conversion fails at the complex rotary-frequency cast under Core ML Tools 9.0 with both Torch 2.14 and the supported Torch 2.7 retry, using NumPy 1.26.4 and explicit float32 conversion. An exact real-pair expression first passes the isolated rotary operator and then both full memory-attention layers. A variable-history export preserves 1–7 complete 512-token spatial memories, 1–16 object pointers split into four tokens each, original per-frame rotary layout and unrotated pointer tokens. Four synthetic history combinations (1/1, 3/3, 7/7 and 7/16 memories/pointers) match original PyTorch with maximum Core ML error 1.32e-6; no padding is used. The caller must retain the original stored-memory bfloat16 roundtrip.

Separate float32 components pass synthetic checks against the original methods: raw image features without a second normalisation or unconditional no-memory embedding (Core ML maximum error 3.10e-5), memory encoding/Perceiver with runtime point-mask versus sigmoid-mask mode (4.85e-4), and supplied-point SAM heads (4.82e-5). The positive-label Torch trace freezes a boolean-index cardinality and cannot run the no-point branch correctly. A separate no-point export preserves original `point_inputs=None` semantics and passes its own parity checks. Model construction, original-wrapper comparison and converted-output comparison remain distinct evidence. Individual component checks do not establish video state, tracking quality or phone performance; the combined and native checks below provide separate evidence.

**Validation boundary:** the app unit/domain/media suite passed 119 tests, with three optional external-media skips and zero failures on iPhone 17 iOS 27.0 Simulator after instrumentation, before the later app integration. Eleven synthetic scorer tests pass, including ambiguous timestamp assignment, candidate-group recall and model provenance. Earlier standalone-device launch attempts were blocked while locked; the current iPhone 18 Pro/iOS 27 is connected with Developer Mode enabled, but no persisted hardware model result exists. Latency, memory and thermals remain pending. Reference-driven exports use the production renderer and supplied positions; their private files are not evidence of automatic tracking.

A first combined video comparison replaces the image, memory, attention and prompt-mode components inside the original Python predictor. The first 32 frames of the existing fixed-crop night middle interval retain exactly matching source PTS, binary masks and centroids: 32/32 nonempty agreement, minimum mask IoU 1.0 and maximum centroid difference 0.0 px. Maximum object-score difference is 0.000275. It includes forward/reverse propagation, growing history and original bfloat16 state storage. Root independently compared all mask bytes and coordinates. The substituted diagnostic takes 33.80 seconds with Core ML `ALL` on the Mac; original Torch uses CPU. This includes helper/crop/PNG/state overhead and is not phone latency or a pure inference benchmark. Earlier incomplete CPU-only bridge runs are preserved. The later moving-crop and native checks below supersede the first two open gates; signed-phone measurements remain unverified.

The full adaptive Core ML bridge now matches the CPU control at every source time, nonempty decision, crop transition and termination. Daylight has identical masks, 104 nonempty frames and nine resets. Night has 104 nonempty frames and seven resets; one foreground pixel differs, giving minimum binary IoU 0.99875 and maximum centre difference 0.0234646 pixels. Both satisfy the predeclared numerical gate (no timing/status/history differences, IoU at least 0.9 and centre difference at most 0.5 pixels). Strict byte identity fails for that night mask. The original report incorrectly represented any PNG-byte difference as IoU zero; it is preserved alongside the executed scorer and an offline corrected sidecar. Synthetic checks distinguish different PNG encodings from different foreground pixels and reject missing required masks.

Standalone Swift now owns image preparation, Core ML calls, temporal/pointer memory and mask extraction. Its 32-frame fixed-crop night run matches original Torch CPU masks and centres exactly, including reverse propagation, with zero RGB normalisation error and positional-encoding maximum error 5.96e-8. It takes 7.35 seconds on the Mac including fixture/model setup. This is not a pure model or physical-phone benchmark. The source reader initially changed RGB values by bypassing Core Image on identity transforms; removing the shortcut yields exact equality for all 153 daylight and 124 night cached frames, and all 233/199 source timestamps and dimensions. Both sources have identity transforms, so nonidentity rotation still needs its own check.

The first full native adaptive run was interrupted after 18 callback masks to investigate PNG colour handling and remains invalid/unscored. The completed second run subsequently passes both full intervals: all 130 daylight callback masks are binary-identical; 117/118 night masks are identical, with one differing foreground pixel (minimum IoU 0.99875, maximum centre difference 0.0234646 px). Canonical PTS, visibility, reset history and termination agree. The output retains 120 daylight and 110 night canonical frames, with 104 nonempty observations each. Native Mac tracking takes 41.737 and 34.936 seconds respectively; these are not phone timings or fresh localisation-accuracy measurements.

The direct-original-video pull provider separately matches all selected PTS and full-source indices, all 18 inspected RGB decodes and eight crop tensors across both sources. It retains at most one RGB frame, reuses forward decoding and verifies actual PTS after reverse/random access; this is not total peak-memory evidence. No model inference occurs in this provider check. Both supplied sources have identity transforms, so rotation remains unverified. Reproduction is in [the native guide](../../Tools/TracerHarness/Native/README.md).

The reference-driven renderer exported the longest contiguous reviewed-visible block from each clip: 107 daylight and 103 night positions. Decoded MP4 frame counts match those block counts. Sample inspection now uses bounded image-generator tolerance and records actual output/source time; sample offsets are up to 3.33 ms for daylight and 18.33 ms for night. Initial default-tolerance thumbnails and compressed decode-order counts were unsuitable for this check and were superseded. The corrected samples show the intended path placement, with the production trail lag preserved; this is sampled Mac rendering evidence, not a complete per-frame or signed-phone alignment proof.

A separate assisted-prediction export now feeds all 100 contiguous night corridor predictions through the exact production exporter, without reference-based filtering. Its decoded MP4 has 100 frames over 3.333 seconds. The sidecar records detector prediction, one supplied point, crop/interval assistance, no autonomous acquisition, source/input/model hashes and actual sample timestamps. Sampled placement is consistent with the predicted path; the production label does not remove the recorded assistance or create a phone accuracy claim.

The later common-policy night export retains all 104 contiguous model predictions over 3.467 seconds, including the one uncertain-reference position, with no accuracy-based filtering. Its sidecar preserves the canonical prediction hash, model/configuration identities, seven automatic resets and explicit active dropout policy. The renderer accepts both structured and flat model provenance without changing coordinates. This is an assisted model preview, not 104 verified ball centres.

Keep these two known clips as development regressions. Independent reference review, complete owner-clip coverage and the 20–30-clip held-out positive/negative matrix remain required. See [ADR 0015](decisions/0015-source-timed-tracer-benchmark.md) and [benchmark instructions](../../Tools/TracerHarness/README.md).

### Ronde point-assisted integration gate

The owner then authorised tracer-only integration into Ronde, preserving default automatic tracking. The local app shares the eight validated native files, loads identity-checked resources through `EdgeTAMTrackingService`, adapts every canonical record including empty masks into `SeededModelTrace`, and renders separated point-assisted segments in preview/export. A clear source-frame point and a cut of at most ten seconds remain explicit assistance. [ADR 0017](decisions/0017-opt-in-on-device-ball-tracking.md) records the accepted boundary.

Resource packaging initially failed, then the offline preparation script verified the five compiled model trees and constants, included the licence and generated the identity manifest; XcodeGen succeeded. The app suite then passes 127 checks with two skips and zero failures on Xcode 27.1/iPhone 17 iOS 27 Simulator: 108 XCTest cases including two skips plus 21 Swift Testing checks, including four seeded-trace and two retry-preservation regressions (`Test-Ronde iOS-2026.09.19_22-19-48-+1000.xcresult`). The separate point-selection UI check also passes frame loading, disabled-before-selection, tap activation, clearing on frame change and close-to-Studio behaviour (`ronde-tracer-point-selection-ui.xcresult`).

The opt-in physical-device test exercises the real app service, adapter, production short-MP4 export and archive round-trip on two private clips, checks source hashes and preserves actual canonical JSON/export attachments. It skips on Simulator or absent fixture configuration. The signed Release test build, strict code-signature check and all five model identities pass; execution could not start because Xcode reported the iPhone 18 Pro/iOS 27 locked; the later CoreDevice access check was unavailable. The preflight wait was cancelled without inference. A separate clean Release app also passes strict signing and all model/constant hashes, without a test bundle or private media. A test pass will establish that bounded integration path, not held-out accuracy, complete-flight recovery, physical interaction usability or memory/thermal safety. No physical Ronde tracking result is claimed yet.

## Historical evidence through 30 August

The older “passed” tracker checks below mean that source/selector regression conditions passed. They are not independently labelled localisation-accuracy results. Estimated path/carry treatments in these historical entries were subsequently removed from the active automatic overlay.

| Evidence | Result | Boundary |
| --- | --- | --- |
| Synthetic timebase tests | Passed at 25, 30, 50, 60, 120 and 240 fps on iPhone 17 Pro iOS 26.5 Simulator | Proves selector and sampling invariance only, not detector accuracy on decoded footage |
| Three supplied private positive clips | Exact production tracker passed two 4K landscape daylight clips and one 4K portrait night-range clip on macOS and iPhone 17 Pro iOS 26.0 Simulator | Positive regression evidence only; clips are not retained in the repository and do not replace a held-out matrix |
| Five-video TestFlight check | One video displayed an automatic tracer; that path was not visually accurate | Signed-iPhone product evidence that current recall and geometry are unacceptable; exact clips are not yet labelled locally, so per-stage causes remain unknown |
| Representative held-out matrix | Not supplied | Blocks accuracy, false-tracer and cross-source reliability claims |
| Physical iPhone performance | Not run | Blocks latency, memory, battery and thermal claims |
| Golf-specific fine-tune | Not run | No licensed, consented golf training set is present; the official upstream repository documents evaluation but its training section remains `TBA` |
| Distance and apex-height ground truth | Not supplied | Blocks precise or calibrated carry and physical apex-height claims; a passing perspective fit may show only a broad uncalibrated carry range |

## 30 August positive regression

Three owner-supplied originals remained outside Git and were temporarily installed only into a disposable signed test bundle. The exact Swift decoder, packaged Core ML model, acquisition guard and selector passed all three on iPhone 17 Pro iOS 26.0 Simulator. After the memory correction, the single external-matrix test passed again with zero skips or failures in 1,397.075 seconds on Simulator without iPhone Neural Engine acceleration; this is regression evidence, not a device-latency benchmark.

| Opaque clip | Source | Impact anchor | Final observed result | Local diagnostic cost |
| --- | --- | --- | --- | --- |
| Landscape A | 3840 x 2160 H.264, about 30 fps, 6.315 s | 1.6320 s audio | 7 points, confidence 0.307; launch around `(0.532, 0.273)` | 30 decoded, 29 sampled, 18 model windows, 975 tiles |
| Landscape B | 3840 x 2160 HEVC, nominal 30 fps, 7.725 s | 0.8747 s audio | 86 points, confidence 0.828; launch around `(0.754, 0.199)` | 116 decoded, 115 sampled, 104 model windows, 3,217 tiles |
| Portrait C | 2160 x 3840 H.264, about 30 fps, 6.618 s | 1.6747 s audio | 82 points, confidence 0.712; launch around `(0.563, 0.351)` after trimming pre-ball club/body motion | 115 decoded, 114 sampled, 101 model windows, 4,985 tiles |

### Landscape A completed-path and export probe

The current working tree was also exercised against the original Landscape A source through the exact AVFoundation decoder, packaged Core ML model, selector, impact-timed perspective completion and traced-video exporter. To make the diagnostic repeatable without spending another full-frame matrix run, model inference was restricted to two known Landscape A source tiles. This proves the supplied clip can drive the corrected completion and renderer when ball evidence is acquired; it does not prove production full-frame acquisition recall.

- Audio impact: `1.6320 s`.
- Diagnostic cost: 28 decoded frames, 27 sampled frames, 15 model windows, 30 tile predictions and 12 candidates.
- Observed evidence: 11 selected mid-air points, confidence `0.417`, from approximately `(0.532, 0.273)` to `(0.522, 0.131)`. A separate compact-object disappearance check anchored launch at `(0.524, 0.752)`; the manually labelled stationary ball was approximately `(0.523, 0.755)`, an error of roughly six source pixels on the 3,840 x 2,160 frame.
- Estimated completion: 16-point launch connector, 250-point continuation, image-space apex around `(0.515, 0.122)` and bounded landing around `(0.488, 0.494)`. The same observed path formerly produced a foreground-return landing around `x = 0.404` because it carried the final join residual unchanged; the residual now reaches zero and lateral displacement remains within the observed-direction cap.
- Carry presentation: `150–220 m`, labelled `MODEL CARRY` and `ESTIMATE · UNCALIBRATED`. This is a prior-driven model range, not a validated measurement.
- Rendered output: 3,840 x 2,160, 190 frames at 30 fps, duration 6.333 seconds. The run demonstrates source-time, ordering and bounded-corridor invariants: original model time was preserved through apex, only descent compressed, and `EST. LANDING` plus carry appeared only at completion with a 120 ms final hold. The latest owner frame review still rejects the visible apex, path and landing placement as off. This is therefore not validation of visual flight, modelled landing or carry accuracy.
- Export runtime boundary: the exact production sources complete this 4K export in a macOS harness. The iOS 26.5 Simulator compositor terminates in its Core Animation IOSurface/XPC path during exporter integration, so a signed physical-iPhone traced export remains required.

This is one owner-supplied positive and one rendered-output inspection. It does not validate distance accuracy, physical-device performance, other framing or the required positive/negative matrix.

The incident was a false-acquisition failure, not an overlay coordinate conversion. The former search narrowed around the first high-confidence coherent moving peak, which could be foliage, compression detail, club or body motion and permanently exclude the later-visible ball. Acquisition now lets full-frame track hypotheses compete through the post-impact launch window, requires eight linked detections before narrowing to a local ROI or displaying a later trimmed path, and trims an early detector hand-off before labelling points observed. If no defensible path remains, the existing no-tracer state still wins.

### Memory-pressure regression

The same production-code diagnostic exposed a separate termination risk: a 5.3 MB Core ML input tensor was allocated once per tile rather than once per model window. Landscape B therefore allocated 3,217 large tensors and reached a measured 19.19 GB peak process footprint. The implementation now reuses one input tensor across every tile in a three-frame window and encloses each synchronous prediction in its own autorelease pool. The observed tracks and confidence values were unchanged.

| Opaque clip | Model windows / tiles | Peak footprint after correction | Maximum resident memory after correction |
| --- | ---: | ---: | ---: |
| Landscape A | 18 / 975 | 235 MB | 578 MB |
| Landscape B | 104 / 3,217 | 699 MB | 1.04 GB |
| Portrait C | 101 / 4,985 | 678 MB | 1.02 GB |

These are macOS diagnostic measurements against the exact Swift tracker, not a physical-iPhone benchmark. A fresh hardware run must still confirm that One Shot completes without an OS memory termination and capture device model, OS, runtime, thermal state and peak memory.

### Source-cadence and dense-acquisition probe

- A deterministic 30.087 fps timestamp stream formerly lost every second source frame because its approximately 0.097 ms early arrival missed a one-microsecond eligibility tolerance. The accepted tolerance is now bounded to 2 ms. All 31 regression frames remain eligible, while the existing 25, 30, 50, 60, 120 and 240 fps invariance checks still pass.
- Running the current tennis-domain detector on every accepted acquisition window did not improve identity. The exact full-frame Landscape A test ran for 265.965 seconds on iPhone 17 Pro iOS 26.0 Simulator with CPU-only Core ML and returned a displayable but wrong path whose launch `y` was `0.3903`, outside the labelled `0.20...0.30` mid-air corridor. That experiment was removed; it is negative model/association evidence, not an accuracy gain.
- A separate post-lock 2x crop presented a smaller predicted-position source region in the detector's 512 by 288 input while leaving acquisition and reacquisition at native scale. The complete three-video production matrix passed in 992.403 seconds, but observed-point counts remained exactly 7, 86 and 82 and launch coordinates remained effectively unchanged. The negligible confidence movement did not establish better localisation or identity. The crop was removed because it added inference work without extending any observed track.
- The optional matrix now protects the established 7, 86 and 82 point counts in addition to the labelled launch corridors. This is a regression floor for these three positives, not a representative accuracy threshold.
- The latest TestFlight field check remains one inaccurate trace from five videos. The exact sources must be transferred, consented and labelled before the four misses can be split among impact timing, detector recall, association and path-completion failure.

## Acceptance thresholds

Thresholds must be set only after the labelled matrix exists. Report acquisition recall on positives, false-tracer rate on negatives and target-golfer association errors separately. A lower frame rate may reduce evidence quality, but must never change eligibility rules or cause timestamps to be inferred from nominal FPS.
