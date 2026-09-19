# Operations

## Prerequisites

- Xcode compatible with the checked-in project.
- XcodeGen when changing `project.yml`.
- Supabase CLI or an authenticated Supabase project connector when changing hosted metadata schema.
- A configured development team only for signing or hardware work.
- The ignored `.local-models` link to verified external EdgeTAM build resources. The main `project.yml` requires these resources; it does not silently omit missing model files. Preparation is described below.
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
xcodebuild -project Ronde.xcodeproj -scheme 'Ronde iOS' -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Ronde.xcodeproj -scheme 'Ronde iOS' -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test
```

After changing `project.yml`, regenerate deliberately and inspect the generated diff. The iOS target is universal (`TARGETED_DEVICE_FAMILY=1,2`) and light-only, with camera, microphone, photo-library and Sign in with Apple capability configuration plus the exact Supabase Swift package. Do not treat the checked-in generated project as updated until regeneration has been reviewed.

The iOS test target is `Ronde iOS AppTests`. Keep tests focused on deterministic media range arithmetic, local media behaviour, account-scoped archive isolation, reversible edit settings, social export/audio, archive failure recovery, proposal/evidence decisions, import routing, audio/body-motion grouping, timestamp-based track association, evidence-anchored completion, capture-quality classification and tracer timing/geometry. The current baseline is recorded in `CURRENT_STATE.md` after each final run. A separate signed local probe may bundle a private clip temporarily, but it must pass the exact Swift decoder, Core ML and linker path and every temporary copy must then be removed. Re-run after changing detector, pixel conversion, association, extrapolation, export or display eligibility.

## Reviewer validation boundaries

The current native implementation passed the unit/media and iPhone UI suites, plus focused iPad and Duo journeys. See [Current State](CURRENT_STATE.md#verification) for dated destinations, result bundles and exact counts. Hardware and service checks remain separate.

### Reproducible tracer experiments

Use [`Tools/TracerHarness`](../../Tools/TracerHarness/README.md) for production-code diagnostics and scoring. The wrapper requires an external output directory; the compiled runner also checks the source working-tree boundary, including symlinks. Keep originals, crop configurations, reference JSON, predictions and rendered derivatives outside Git. Only the explicitly synthetic examples may be committed. Compile the reference extractor with an absolute source path so its boundary check is independent of the caller's working directory.

For each run, retain the exact model/source hashes, source byte hash, encoded and upright dimensions, source PTS, configuration and assistance in the private manifest. Use the upright dimensions for localisation errors. A controlled impact is supplied assistance and does not test automatic audio/body impact selection. Prompted-model reports also disclose source crop corridors, input resizing, temporal intervals, point prompts and corrections. Do not reuse output visibility or whole-track confidence as a calibrated accuracy score.

The scorer separates timestamp availability from within-tolerance visible-frame coverage, reports raw and uncertainty-aware pixel error, and evaluates all candidates in the matched source-time group. Non-visible reference states break missing/wrong-position runs. Report both 4- and 12-source-pixel thresholds as diagnostic comparisons, not agreed release thresholds. Real reference labels require independent human review before they can be described as ground truth; unlabelled or uncertain flight never counts as a success.

Alternative-model dependencies and checkpoints stay in a separate local environment. Verify code and weight licences at the selected revision. The BootsTAPIR and EdgeTAM adapters are Mac research comparators; neither MPS timing nor visibility/mask counts establish phone speed or correct ball positions. Preserve raw masks and source-time mappings for segmentation-derived points. See [ADR 0015](decisions/0015-source-timed-tracer-benchmark.md) and the dated [validation ledger](TRACER_VALIDATION.md).

The [standalone device probe](../../Tools/TracerHarness/Device/README.md) uses a separate bundle and privately staged media/configuration. Review source/config/model identity before installation, retain per-clip completed evidence, and distinguish sampled per-clip memory from process-lifetime peaks. Remove disposable probe media after measurements are complete.

### Runtime and release checks

- Simulator builds can validate compilation and basic layout only. They do not prove camera capture, microphone timing, long-source performance, rolling-buffer correctness, thermal limits or ML/tracer quality.
- Physical-device validation remains outstanding and must cover one-shot imports up to 60 seconds plus manual recording imports up to 20 minutes, source preservation, bounded long-source frame inspection, bookmark boundary handling, duplicate-safe batch extraction, processing latency, peak memory, thermal behaviour, playback and traced export. Permission denial and background/foreground interruption remain relevant; automatic moment suggestions, hands-free capture, automatic replay and rolling-buffer cleanup remain deferred workflows.
- Use `TRACER_VALIDATION.md` as the validation ledger. Tracer reports must include source format, camera angle, presentation-rate summary, detector revision, observed-point count and span, provenance, confidence, cost metrics and whether a visible tracer was withheld. Uploaded frame rate never acts as an import rejection rule.
- There is no unconditional estimated-path fallback. Generic Vision moving-shape observations are diagnostic only and must never become visible tracer geometry. A failed ball-evidence gate must render `Ball flight not tracked`. The active studio and social exporter use accepted observed samples only. The older estimated-flight renderer remains a separate experiment under ADR 0011.
- When the optional source-frame launch anchor is accepted, compare its coordinate with the labelled stationary ball at impact and record the source-pixel error. The frame-difference check must reject multiple similarly plausible bright objects and must never make a clip tracer-eligible without the separate source-timed mid-air track.
- When probing Vision trajectory code, pass the `CMSampleBuffer` to `VNSequenceRequestHandler`. Passing only its pixel buffer removes presentation time and causes stateful trajectory analysis to fail. Do not assign media timestamps to `targetFrameTime`; Apple defines that property as a real-time processing deadline.
- `GolfBallTracker.mlpackage` is the official NTT WASB-SBDT tennis weight converted to Core ML. Keep `WASB-SBDT-LICENSE.txt` and `WASB-SBDT-NOTICE.txt` with the model, and verify the recorded PyTorch and Core ML hashes after any replacement. Do not substitute weights without commercial distribution provenance.
- The iOS Simulator path uses CPU-only Core ML. WASB retains automatic compute-unit selection on physical iPhone; EdgeTAM now requests CPU/Neural Engine following the reported first-inference crash, with GPU excluded as a containment measure. The crash cause and the new device policy remain unverified until the phone rerun. Mac EdgeTAM parity still uses all compute units. Treat Simulator/Mac performance as diagnostics, never as iPhone latency or energy evidence.
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
- If native Apple sign-in fails with `NSURLErrorDomain -1003` and the configured project hostname returns `NXDOMAIN`, check the existing project's live Supabase status before changing authentication code or credentials. A paused (`INACTIVE`) project needs to be resumed. Verify `ACTIVE_HEALTHY`, DNS resolution, a successful `/auth/v1/health` response and Apple enabled in `/auth/v1/settings`, using only the app's publishable key. These service checks do not replace a fresh signed-device Apple login. See [Supabase project pausing](https://supabase.com/docs/guides/platform/free-project-pausing).
- The migration files in `supabase/migrations/` mirror the hosted versions. Use `supabase link --project-ref apaowuzliauwxbxylfpk` followed by `supabase db push --linked` only from an authenticated operator environment, and inspect the migration plan before applying it.
- `profiles` and `library_items` must retain row-level security, per-user ownership policies and revoked anonymous grants. Run the Supabase security advisor after every DDL change.
- The app may contain the public Supabase URL and publishable key. Never place a service-role key, database password, Apple private key or signing secret in source, documentation, logs or previews.
- Apple is enabled under Supabase Auth providers with native Client IDs value `com.ronde` and no OAuth secret. Preserve that native-only configuration. Enable Sign in with Apple for the matching App ID in the Apple Developer portal. The native token exchange does not require browser OAuth redirects, but the Apple portal state and a signed-device login must be verified before release.
- Metadata sync is best-effort and must not block local review after an account has activated its archive. The current client upserts device metadata and deletes matching hosted rows; it does not pull remote rows or restore missing local media.

## Preview states

The iOS Debug build accepts `ios-redesign-signin`, `ios-redesign-home`, `ios-redesign-library`, `ios-redesign-profile`, `ios-redesign-media`, `ios-redesign-tracer`, `ios-recording-studio` and `ios-quick-review`. The legacy home preview opens Sessions, library opens Shots, profile opens Settings, media/quick-review open Shot Studio, and `ios-recording-studio` opens the manual Recording Studio fixture. Fixtures contain archived observed and estimated segments, but the studio renders observed samples only; `RONDE_PREVIEW_VIDEO_PATH` may point to a local simulator-only source. Never commit the referenced private footage. Treat screenshots as layout evidence only after confirming the exact build, destination and requested state.

## Studio regression checks

`Ronde iOS AppUITests` exercises native library navigation, draft cancellation, playback, Trim/Trace/Format tabs, actual format tiles, recording bookmarks, batch Shot creation, source-linked Shot opening, trimming and export. The bundled `studio-fixture.mp4` is a generated portrait test pattern with audio, not golf footage or tracking validation. Unit encoder tests use the same fixture. The full iOS scheme runs both targets; use `-only-testing:'Ronde iOS AppTests'` or `-only-testing:'Ronde iOS AppUITests'` for a focused follow-up. Update `CURRENT_STATE.md` with the final result bundle rather than relying only on console test counts.

When other tasks are running UI tests, use a dedicated Simulator destination ID and `-parallel-testing-enabled NO`; do not terminate another task's app or test process. Run the two Session/recording journeys on wide layouts and the largest accessibility text size, then restore the device setting. Multi-display Duo screenshots may require an explicit active display; black inactive-display captures are not visual evidence. Simulator rotation verifies layout continuity, not physical folding.

Check all output canvases for aspect fit, correct portrait orientation, trace alignment, selected duration and audible audio. Test cancel/retry and silent sources separately. Export files use the app's local temporary directory; original source files must retain their hash. Verify the actual share destination on a signed device before claiming an end-to-end social-platform integration.

## TestFlight packaging

- The iOS product is named `Ronde Shot Review` for App Store Connect record creation while `CFBundleDisplayName` remains `Ronde` on the device.
- The universal iOS AppIcon reuses the current approved 1024 px Ronde artwork and compiles into iPhone and iPad icon variants.
- An App Store Connect error that the app name is already in use is an app-record naming conflict. Create or select the `com.ronde` app record using the unique product name, then upload the archive to that record.
- `project.yml` is the authority for the universal iOS bundle ID, capabilities and build settings. Regenerate the Xcode project after any change. Bundle identifiers are case-sensitive on-device.
- A generic-device archive has succeeded with the compiled universal icon. The inspected archive was Apple Development-signed, so App Store distribution signing, record selection and TestFlight availability remain portal-level evidence.


### Native tracer diagnostics

Use [the native guide](../../Tools/TracerHarness/Native/README.md) to compile exactly one diagnostic runner with the shared Swift sources. The app also includes the same eight `EdgeTAM*.swift` runtime files. Keep model packages, learned embeddings, source fixtures and outputs outside Git. Full native Mac adaptive parity and direct-video RGB/tensor checks pass; physical-device integration remains separate. Do not call an interrupted or deadline-limited run a full-interval result. Preserve failed outputs and exact executed source hashes before changing conversion or scoring code.

### Point-assisted app resources and device test

The offline [`prepare-edgetam-app-models.py`](../../Tools/TracerHarness/scripts/prepare-edgetam-app-models.py) consumes an already-built diagnostic app and its verified build evidence. It validates the five complete compiled-model trees and learned constants, copies only required resources to an external directory, and writes `edgetam-model-identity.json`. Include the Apache-2.0 licence as `edgetam-license.txt`. It does not download a model or access private source video. The app service independently validates the bundled hashes before each operation and loads models only for that operation.

Set these operator-local environment variables to authorised external paths; do not save their values in the repository. Create the `.local-models` symlink only if absent, or verify the existing link before reuse.

```sh
python3 Tools/TracerHarness/scripts/prepare-edgetam-app-models.py \
  --app "$RONDE_EDGETAM_DIAGNOSTIC_APP" \
  --evidence "$RONDE_EDGETAM_BUILD_EVIDENCE" \
  --license "$RONDE_EDGETAM_LICENSE" \
  --output "$RONDE_EDGETAM_MODEL_DIR"
ln -s "$RONDE_EDGETAM_MODEL_DIR" .local-models
xcodegen generate --spec project.yml
```

For the explicitly authorised physical test only, `.local-tracer-tests` links to an external folder with the two private movies and `edgetam-device-test-config.json`. The configuration uses the diagnostic's clip schema, including source hashes, upright dimensions, selected interval and source-frame point; it contains no reference labels. `project-tracer-device-test.yml` adds these resources to the XCTest target only. Never use this variant for distribution or commit its private resources/generated additions.

```sh
xcodegen generate --spec project-tracer-device-test.yml
xcodebuild -project Ronde.xcodeproj -scheme 'Ronde iOS' \
  -destination "id=$RONDE_TEST_DEVICE_ID" \
  -only-testing:'Ronde iOS AppTests/EdgeTAMDeviceIntegrationTests' \
  -resultBundlePath "$RONDE_EDGETAM_RESULT_BUNDLE" test
xcodegen generate --spec project.yml
```

The test skips on Simulator or absent configuration. It calls the real bundled app service, retains source PTS/indices, masks-as-gaps and model identity, exports a short observed segment with `ShotVideoExporter`, checks source preservation and archive round-trip, and retains private JSON/MP4 attachments plus app-Documents evidence. Its cooperative deadline is 470 seconds with a 480-second XCTest allowance. Inspect those actual results before claiming phone success; a launch, compile or skipped test is not model evidence. Test cancellation/account ownership and the zoom/select interaction separately. App tracking/export never reads reference labels or fills absent points; offline reference scoring is separate.

## Release evidence levels

Keep these claims separate:

1. Source inspection.
2. Xcode project generation.
3. Simulator build.
4. Simulator interaction.
5. Physical iPhone/iPad interaction and permission behaviour.
6. Archive and signing.
7. TestFlight or App Store availability.
