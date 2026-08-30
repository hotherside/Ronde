# Operations

## Prerequisites

- Xcode compatible with the checked-in project.
- watchOS 10+ simulator runtime.
- XcodeGen when changing `project.yml`.
- Supabase CLI or an authenticated Supabase project connector when changing hosted metadata schema.
- A configured development team only for signing or hardware work.
- A fixed tripod and down-the-line capture setup for reviewer validation. Use synthetic or consented test footage only; do not place private range footage in the repository.

## Inspect schemes

```bash
xcodebuild -project Ronde.xcodeproj -list
```

## Regenerate the project

`project.yml` is the configuration source. Review the generated diff before keeping it.

```bash
xcodegen generate
git diff -- Ronde.xcodeproj project.yml
```

## Build

```bash
xcodebuild -project Ronde.xcodeproj -scheme 'Ronde Watch App' -destination 'generic/platform=watchOS Simulator' build
xcodebuild -project Ronde.xcodeproj -scheme 'Ronde iOS' -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Ronde.xcodeproj -scheme 'Ronde iOS' -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test
```

After changing `project.yml`, regenerate deliberately and inspect the generated diff. The iOS target is universal (`TARGETED_DEVICE_FAMILY=1,2`) and light-only, with camera, microphone, photo-library and Sign in with Apple capability configuration plus the exact Supabase Swift package. Do not treat the checked-in generated project as updated until regeneration has been reviewed.

The iOS test target is `Ronde iOS AppTests`. Keep tests focused on deterministic media range arithmetic, local media behaviour, account-scoped archive isolation, honest library metrics, proposal/evidence decisions, import routing, audio/body-motion grouping, timestamp-based track association, evidence-anchored completion, capture-quality classification and tracer timing/geometry. The current baseline is recorded in `CURRENT_STATE.md` after each final run. A separate signed local probe may bundle a private clip temporarily, but it must pass the exact Swift decoder, Core ML and linker path and every temporary copy must then be removed. Re-run after changing detector, pixel conversion, association, extrapolation, export or display eligibility.

When selecting a named watch simulator, Xcode can expose paired and standalone devices with the same name. Use `-showdestinations` and an explicit `id=<SIMULATOR_ID>` when a name is ambiguous. Do not commit machine-specific simulator IDs to the canonical command.

## Reviewer validation boundaries

- Simulator builds can validate compilation and basic layout only. They do not prove camera capture, microphone timing, rolling-buffer correctness, thermal limits or ML/tracer quality.
- Physical-device validation remains outstanding and must first cover short shot-video imports up to 60 seconds, processing latency, peak memory, thermal behaviour, playback and traced export. Permission denial and background/foreground interruption remain relevant; a one-shot Live Review loop, long Range Session, automatic replay and rolling-buffer cleanup are deferred workflows rather than current MVP gates.
- Use `TRACER_VALIDATION.md` as the validation ledger. Tracer reports must include source format, camera angle, presentation-rate summary, detector revision, observed-point count and span, provenance, confidence, cost metrics and whether a visible tracer was withheld. Uploaded frame rate never acts as an import rejection rule.
- There is no unconditional estimated-path fallback. Generic Vision moving-shape observations are diagnostic only and must never become visible tracer geometry. A failed ball-evidence gate must render `Ball flight not tracked`. Only a passing source-timed ball launch may seed the lower-opacity, explicitly labelled estimated ranges of the solid-purple ribbon.
- When the optional source-frame launch anchor is accepted, compare its coordinate with the labelled stationary ball at impact and record the source-pixel error. The frame-difference check must reject multiple similarly plausible bright objects and must never make a clip tracer-eligible without the separate source-timed mid-air track.
- When probing Vision trajectory code, pass the `CMSampleBuffer` to `VNSequenceRequestHandler`. Passing only its pixel buffer removes presentation time and causes stateful trajectory analysis to fail. Do not assign media timestamps to `targetFrameTime`; Apple defines that property as a real-time processing deadline.
- `GolfBallTracker.mlpackage` is the official NTT WASB-SBDT tennis weight converted to Core ML. Keep `WASB-SBDT-LICENSE.txt` and `WASB-SBDT-NOTICE.txt` with the model, and verify the recorded PyTorch and Core ML hashes after any replacement. Do not substitute weights without commercial distribution provenance.
- The current iOS Simulator path forces the Core ML model to CPU-only execution because the packaged model triggers an MPSGraph invalid-state failure in the installed Simulator runtime. Physical iPhone builds retain automatic compute-unit selection. Treat Simulator model performance as functional diagnostics only, never as device latency or energy evidence.
- The packaged model is not release-quality merely because one signed clip passed. Record held-out track precision, missed-ball rate, false-tracer rate and physical-device latency, memory and thermal evidence before shipping the reviewer as production tracking.
- Include a near-30 source such as the 30.087 fps timestamp regression in cadence tests. Source frames arriving within 2 ms of the target cadence should remain eligible; 50, 60, 120 and 240 fps inputs must still remain bounded near 30 Hz. Do not increase acquisition density merely to raise candidate count: the 30 August every-window Landscape A probe selected the wrong object at `y = 0.3903` instead of the labelled `0.20...0.30` corridor. Do not add a magnified post-lock crop unless it extends labelled observed evidence: a 2x crop preserved the same 7, 86 and 82 point tracks across the three private positives while adding inference work.
- Treat the competitive 0.65-second full-frame acquisition window, eight-detection commitment gate, local-ROI tracking and four-second analysis cap as performance policy. Capture the emitted decoded/skipped/sampled frame counts, model windows, model input allocations, tiles, full/local/reacquisition searches, candidates and selected points for every benchmark clip. Assert that input allocations do not exceed successful model windows. Profile both resident memory and process footprint after tracker, frame-decoder or model changes; the 30 August local baseline was about 235 MB, 699 MB and 678 MB peak footprint for the three supplied positives, down from 19.19 GB on Landscape B before tensor reuse. These macOS diagnostics do not replace a physical-iPhone memory run. A launch-lock change must rerun the external false-acquisition regression as well as deterministic selector tests. The private three-clip matrix is explicitly opt-in with `RONDE_RUN_EXTERNAL_VIDEO_MATRIX=1`; provide all three opaque named resources in a disposable signed test bundle or let the test remain skipped. Never add the source media to the repository.
- Range automatic analysis may be enabled only after confirming all three session conditions in the UI: fixed or braced camera, target golfer explicitly confirmed, and no other golfer in frame. If any condition is false or unknown, leave the detector unavailable and the moment uncertain.
- Traced-video export must consume the stored reviewed geometry. It must not rerun detection or change an observed, estimated or manual provenance label during export.
- Inspect tracer timing frame by frame from the stationary launch ball through the first observation, each sparse detector interval, apex, final observation and landing. The solid ribbon must start at the accepted launch anchor, remain behind the visible ball during the observed range and continue without a seam or bulk second-stage reveal; `EST. APEX`, `EST. LANDING` and carry must not appear before their coordinates are reached. For a source shorter than the model duration, compare the original and mapped apex times, verify the sampling-derived lag never exceeds 50 ms, confirm that only post-apex descent is compressed and keep the completed-path hold at or below 120 ms. If apex plus lag cannot fit, landing and carry must remain hidden. Check that the final continuation retains any robust observed lateral direction, stays within the last-observation-to-bounded-landing corridor plus `0.008` padding and does not return onto foreground golfer geometry. Never replace source timestamps with point-count progress or animate model geometry as though it were observation. Exporter probes should verify both the media container and rendered frames. The current iOS 26.5 Simulator Core Animation compositor can terminate with an IOSurface/XPC API-misuse trap, so record that separately and repeat traced export on a signed physical iPhone.
- Live capture targets 60 fps and settles/locks focus, exposure and white balance where supported. Stability and framing guidance are readiness signals only. They do not prove the rolling writer, automatic replay or a completed hands-free shot loop.
- A broad carry range may be shown only when several bounded, similarly plausible perspective fits pass the observed-ball gate, and it must remain labelled `MODEL CARRY` and `ESTIMATE · UNCALIBRATED`. Screen displacement may select a broad shot-speed prior, but it must not be described as measured launch speed. Precise or calibrated carry and physical apex height are not operationally valid until camera calibration and known-ground-truth comparison are documented.

## Supabase and Apple account configuration

- Hosted project: `apaowuzliauwxbxylfpk`.
- The migration files in `supabase/migrations/` mirror the hosted versions. Use `supabase link --project-ref apaowuzliauwxbxylfpk` followed by `supabase db push --linked` only from an authenticated operator environment, and inspect the migration plan before applying it.
- `profiles` and `library_items` must retain row-level security, per-user ownership policies and revoked anonymous grants. Run the Supabase security advisor after every DDL change.
- The app may contain the public Supabase URL and publishable key. Never place a service-role key, database password, Apple private key or signing secret in source, documentation, logs or previews.
- Apple is enabled under Supabase Auth providers with native Client IDs value `com.ronde` and no OAuth secret. Preserve that native-only configuration. Enable Sign in with Apple for the matching App ID in the Apple Developer portal. The native token exchange does not require browser OAuth redirects, but the Apple portal state and a signed-device login must be verified before release.
- Metadata sync is best-effort and must not block local review after an account has activated its archive. The current client upserts device metadata and deletes matching hosted rows; it does not pull remote rows or restore missing local media.

## Preview states

The Watch Debug build supports `RONDE_PREVIEW_SCREEN` through `RondePreviewRouter.swift`. The iOS Debug build accepts `ios-redesign-signin`, `ios-redesign-home`, `ios-redesign-library`, `ios-redesign-profile`, `ios-redesign-media`, `ios-redesign-tracer` and `ios-quick-review`. The media fixtures contain distinct observed and estimated segments; `RONDE_PREVIEW_VIDEO_PATH` may point to a local simulator-only source. Never commit the referenced private footage. Treat screenshots as layout evidence only after confirming the exact build, destination and requested state.

## TestFlight packaging

- The iOS product is named `Ronde Shot Review` for App Store Connect record creation while `CFBundleDisplayName` remains `Ronde` on the device.
- The universal iOS AppIcon reuses the current approved 1024 px Ronde artwork and compiles into iPhone and iPad icon variants.
- An App Store Connect error that the app name is already in use is an app-record naming conflict, not evidence that the Watch target caused the failure. Create or select the `com.ronde` app record using the unique product name, then upload the archive to that record.
- `project.yml` is the authority for companion bundle IDs. Keep the iOS bundle ID and the Watch app's `WKCompanionAppBundleIdentifier` exactly `com.ronde`; regenerate the Xcode project after any change. Bundle identifiers are case-sensitive on-device.
- A generic-device archive has succeeded with the compiled universal icon and embedded Watch app. The inspected archive was Apple Development-signed, so App Store distribution signing, record creation and TestFlight upload remain portal-level evidence.

## Release evidence levels

Keep these claims separate:

1. Source inspection.
2. Xcode project generation.
3. Simulator build.
4. Simulator interaction.
5. Physical watch interaction and permission behaviour.
6. Archive and signing.
7. TestFlight or App Store availability.
