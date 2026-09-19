# 0015: Source-timed tracer evidence before model adoption

**Status:** Local implementation and experiments; not a production accuracy release

**Date:** 19 September 2026

**Later decision:** [ADR 0017](0017-opt-in-on-device-ball-tracking.md) authorises the optional point-assisted app integration after native parity. This record retains the earlier research boundary; it is not a physical-device accuracy claim.

## Context and source

The owner authorised execution of the phone-only tracer research, with Astra owning orchestration and review and bounded work delegated to other models. Work began from `main` at `7a6bd012484419faf3f23011cee7f4ae12b4a6b3` on `codex/tracer-evidence-benchmark`. Two owner-supplied original videos are useful acceptance examples, but do not supply a held-out evaluation set. They remain outside the repository and external model services.

The immediate deliverable is a repeatable labelled comparison of detection, association and rendering. A confident-looking trajectory, successful model invocation or passing build cannot establish ball identity. Most retained baseline positions on the reviewed portions are close to the visible ball, while a few large false selections and missing spans remain unacceptable.

## Decision

Keep the production model and default tracking policy while adding an opt-in diagnostic callback and repository-owned benchmark tools. Diagnostics expose source timestamps, candidate positions and confidence, search mode, search region, gate state and selected observations only when explicitly requested. Ordinary application analysis does not retain diagnostic arrays or write private evidence.

Reference annotations carry visibility and review provenance. `agent-reviewed`, `human-verified`, `proposal` and `unreviewed` are distinct states. Unknown or obscured ball positions are not filled by a fitted arc. Blurred centres carry annotation uncertainty, with absolute localisation error still reported. No agent-reviewed reference is represented as independently human-verified ground truth.

Use actual AVFoundation source presentation timestamps and upright source coordinates. A cross-decoder timestamp mismatch was found in one supplied source, so matching by nominal FPS or blindly assigning frame indices is not an acceptable conversion. Scoring checks source identity, dimensions and coordinate conventions and performs explicit timestamp matching without filling gaps.

Report timestamp availability separately from correct localisation, count missing predictions in visible-frame coverage, and test raw candidate recall across every candidate at the matched timestamp. Record supplied impact times, point prompts, temporal intervals, crop corridors and corrections as assistance. A tracker given an impact time is not evidence of end-to-end automatic shot discovery.

Keep model comparisons outside the app until they beat the baseline under declared conditions. Public model code and weights may be downloaded into an isolated local environment; private source footage is not uploaded. A diagnostic three-peak-per-tile variant is an experiment, not a new production default. The recorded BootsTAPIR comparisons do not justify adopting that checkpoint or rejecting every prompted tracker.

An earlier point prompt is also an experiment, not an assumed solution. The first-visible-point replay and a separate native-pixel bright-object comparator both failed to establish reliable identity. A future assisted point must remain a distinct, source-timed input with its own provenance; it must not be inserted into automatic observed geometry or silently replace the current manual annotation type. No new point-assisted product flow is adopted by these comparisons.

EdgeTAM's shared moving-crop and bounded 0.20-second dropout prototype reaches 104/113 daylight and 102/103 night positions within 12 source pixels, using one supplied clear-air point and interval. Empty masks remain unobserved; continuation keeps the same state and crop until an actual mask returns within the source-time bound. Nine daylight positions remain missing, and the blurred night launch centre exceeds the strict tolerance. Keep this experimental policy opt-in. Synthetic Core ML component parity now covers image features, memory/Perceiver, variable-history attention and separate supplied-point/no-point heads. Validate combined video state, independent footage and phone cost before adoption. Preserve preprocessing, conditioning, memory and prompt semantics; a component export or external phone FPS claim is not a validated video pipeline.

The initial native checkpoint verified the Core ML bridge, a 32-frame fixed-crop Swift comparison and source decoder RGB/timing, while an interrupted adaptive run remained unscored. A later bounded full native Mac run passed both intervals, and direct-video RGB/tensor checks passed separately. The interrupted evidence remains preserved. The owner subsequently authorised the app integration in ADR 0017; code integration, interaction, phone cost and representative accuracy remain distinct gates.

## Consequences and next gates

The tools and synthetic tests are portable repository work. Private videos, image crops, reference positions, predictions, model downloads and rendered reference derivatives stay in an explicit owner-controlled external directory. Only aggregate conclusions belong in the context library or its high-level Notion mirror.

The two references remain provisional and incomplete in uncertain late-flight portions. Independent label review, representative negatives and the 20–30-clip evaluation matrix are required before changing the accuracy claim. The next perception work must distinguish missing image detections from selecting the wrong candidate; merely increasing candidate count or fitting a prettier path is insufficient.

Renderer checks use the stored source-timed path. A reference-driven export validates rendering with supplied coordinates, not automatic tracking. Mac inference time and Simulator validation remain separate from signed-iPhone latency, memory, thermal behaviour, cancellation and export evidence. A separately installed diagnostic app must not replace Ronde or touch its archive; temporary probe media copies must be removed after the probe is complete.

See [the validation ledger](../TRACER_VALIDATION.md), [benchmark tooling](../../../Tools/TracerHarness/README.md) and [operations](../OPERATIONS.md).
