# 0017: Optional point-assisted ball tracking inside Ronde

**Status:** Accepted direction; local uncommitted integration, physical-device validation pending

**Date:** 19 September 2026

## Context

The entry flow and ten-second limit below are superseded by [ADR 0018](0018-clip-first-tracing-and-correction.md), following the owner's crash report and clip-first flow feedback. The original evidence remains a dated checkpoint.

The owner explicitly requested that the tracer work continue inside the actual Ronde app, without redesign. Work is on `codex/tracer-evidence-benchmark` from `7a6bd012484419faf3f23011cee7f4ae12b4a6b3`. [ADR 0015](0015-source-timed-tracer-benchmark.md) records the earlier comparisons and their assistance/accuracy limits.

EdgeTAM's common moving-crop/0.20-second dropout policy improves coverage on the two known development clips. Full native Mac adaptive parity and direct-video RGB/tensor checks now pass. Those results justify testing an optional app path; they do not establish automatic acquisition, held-out accuracy or phone performance.

## Decision

- Preserve default WASB automatic review and its evidence gate. Add an explicit `Track ball` action in Shot Studio for a selected cut of at most ten seconds. The user inspects source frames, zooms and chooses one clearly visible ball point. A selected point is assistance, not a detected impact or a model observation.
- Share the eight validated native runtime files with the app through `project.yml`; keep diagnostic runners separate. `EdgeTAMTrackingService` validates actual source PTS/upright dimensions and local resource identity, runs one bounded operation off the main actor, closes the reader and releases models afterwards. No Python, VLM, download or remote media service runs in the app.
- Preserve the frozen model-driven 512-pixel crop, independent forward/reverse tracking, maximum 0.20-source-second empty-mask continuation, 32 automatic resets and 240-second propagation cap. Empty frames have no coordinates; crop movement and automatic reseeding use actual model observations. Budget termination is an explicit partial result.
- Persist point-assisted results separately as `SeededModelTrace`: source-pixel observations, exact frame indices/PTS, nil gaps, the supplied seed/interval and model/constant/policy identity. Never insert the seed or fill missing observations. Preview/export use independent segments and retain the selected-point provenance label; automatic evidence and manual annotations remain intact.
- Protect account generation, source/candidate ownership and cancellation before saving; roll back failed archive mutations. Prevent overlapping automatic and point-assisted work on one source. Preserve separately saved traces during a same-source single-shot automatic retry without inventing multi-shot correspondence.
- Keep model resources external to Git, staged offline through the ignored `.local-models` link with five compiled components, constants, identity manifest and Apache-2.0 licence. Validate complete component trees during preparation and in the app. Private two-clip fixtures are available only to the opt-in device XCTest target.

## Alternatives and consequences

Retaining only the current automatic tracker leaves substantial missing flight and some wrong-object selections. Replacing its default with a prompted model would misrepresent acquisition and impose a new mandatory step; the accepted action is optional. A manual curve remains useful but must remain a separately authored annotation. Cloud media/VLM processing is outside the local-first contract.

The integration suite passes 127 checks with two skips on Simulator, and the separate point-selection UI check passes. The signed device-test build and model identities are verified; physical Ronde inference, source-frame interaction, segmented export, archive behaviour, cancellation, memory and thermals remain pending. The actual device test retains source/model-verified canonical JSON and short MP4 exports privately. Independently reviewed labels, representative negatives and held-out footage remain necessary before an accuracy release. This decision authorises a local implementation and device validation, not production distribution.

See [Current State](../CURRENT_STATE.md), [validation](../TRACER_VALIDATION.md) and [resource/device operations](../OPERATIONS.md#point-assisted-app-resources-and-device-test).
