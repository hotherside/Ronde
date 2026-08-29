# Current State

**Reviewed:** 29 August 2026

**Release branch:** `codex/ronde-shot-reviewer-v1`; this branch is the active reviewer implementation lane. `main` currently points to `823c10d`.

**Release-candidate scope:** independent watchOS shot-counter hardening plus the accepted universal iPhone/iPad Shot Reviewer expansion.

## Stage

Ronde is in pre-release product hardening and reviewer usability testing. The release candidate contains the core watch golf round flow plus the substantial reliability and visual pass. The iPhone reviewer has an automatically playing video-first one-shot path, audio-led impact timing, an integrated free on-device sports-ball tracker and a fail-closed long-session decision pipeline. The fabricated estimated tracer has been removed: real uploads now draw the model's observed source-timed segment only when its temporal evidence gate passes, otherwise they draw nothing. One supplied clip passed end to end; held-out accuracy, long-session target-golfer association, physical-device performance, capture automation and distribution remain open gates.

## Capability status

| Capability | Status | Current truth |
| --- | --- | --- |
| watchOS product | Implemented | Standalone watchOS 10+ SwiftUI app; it remains the independent core shot counter. |
| iPhone/iPad reviewer contract | Accepted | Universal light-theme reviewer with direct single-shot playback, evidence-backed tracer gating, multi-shot Range Session segmentation, Live Review, editable impact-5/+5 clips and local-only processing. See ADR 0006. |
| iPhone/iPad reviewer vertical slice | Implemented locally | Local Photos/Files import, explicit One Shot/Range Session routing, audio/body-motion proposal cues, logical impact-5/+5 playback and portrait-safe video are present. One Shot reviews autoplay once. A tracer renders only for a displayable observed track; otherwise the surface says `Ball flight not tracked`. Range reviews prioritise a compact accepted-shot filmstrip and keep uncertain moments in a collapsed no-tracer queue. Share is withheld until rendered derivative export exists. No persistent session library yet. |
| Live Review automatic loop | Missing | In-app Range recording, rolling segment writer, fused hands-free detection, automatic post-roll replay and temporary-buffer cleanup are not implemented. |
| Automatic segmentation and tracer quality | One-shot tracker integrated; release validation open | One Shot uses the packaged MIT WASB-SBDT Core ML model over source-resolution tiles plus a seven-point single-ball linker. The supplied private clip passed the exact signed Swift path. Long-session target-golfer and launch-evidence adapters still report model unavailable, so real Range imports cannot automatically accept shots. Held-out positive/negative metrics and physical-device performance are missing. |
| Round setup | Implemented | Quick 9, Quick 18, manual par and bundled Sydney course selection exist. |
| Shot counting | Implemented | Add, undo and hole transitions exist; Action Button uses App Intents. |
| Local history | Implemented in release candidate | SwiftData stores rounds and hole scores, with recovery and degraded storage modes. |
| Workout session | Implemented in release candidate | HealthKit golf workout supports long-running rounds, recovery and safer ending. |
| Location and walking | Implemented foundation | Nearby-course detection and pedometer support exist; permission and real-device behaviour need validation. |
| Preview routing | Implemented in release candidate | `RONDE_PREVIEW_SCREEN` supports deterministic debug routing. |
| Automated tests | Implemented | `Ronde iOS AppTests` covers impact clustering/cooldown, body motion, clip windows, local media, orientation, non-displayable inferred geometry, source-time tracer reveal/reset, explicit import routing and real-shot gating. The 24 August simulator result is recorded below. |
| Simulator build | Verified 21 August 2026 | Both generic Watch and iOS simulator schemes built. The iOS test target passed on iPhone 17 Pro iOS 26.0. |
| iPhone visual review | Prior layout evidence only | The 22 August pass proved portrait playback layout but displayed the now-removed fixed estimated fallback. It is not tracer-quality evidence. A fresh no-tracer and later observed-tracer visual pass is required. The private clip was not copied into the repository or app bundle. |
| iPad visual review | Verified 22 August 2026 | Fresh iPad Pro 11-inch visual pass completed for the adaptive two-column deterministic Shot Review fixture. |
| Hardware validation | Unverified | Action Button, HealthKit recovery and outdoor legibility need a real Apple Watch pass. |
| Distribution packaging | Archive verified 21 August 2026 | A generic-device archive completed successfully with compiled iPhone/iPad icons and the embedded Watch app. It is development-signed; App Store Connect record selection, distribution signing, upload and TestFlight availability remain unverified. |

## Current risks

- The release candidate is not available from `main` until its pull request is merged.
- Watch scoring, persistence and workout state transitions still have no dedicated automated test target.
- Simulator success cannot prove Action Button or HealthKit behaviour on hardware.
- Location, HealthKit and motion data increase privacy and permission-copy obligations.
- Xcode project changes and `project.yml` must remain synchronised.
- Long video processing, temporary rolling capture and on-device models may expose memory, battery, thermal and storage limits.
- The integrated tracker has one positive private-clip result only. It may still miss different ball colours, daylight, camera angles or resolutions, or falsely follow range clutter. Release requires representative positives and negatives.
- The long-session orchestration is functional but intentionally accepts no production shots while the detector adapter reports model unavailable. This prevents false clips today but does not yet satisfy competitive automatic segmentation.

## Delivery validation refreshed on 29 August 2026

- Regenerated `Ronde.xcodeproj` from `project.yml` and built the `Ronde iOS` scheme for the generic iOS Simulator. The embedded Watch app, universal AppIcon and packaged Core ML model all compiled successfully.
- Ran the `Ronde iOS` suite on an iPhone 17 Pro running iOS 26.0 Simulator: 32 passed, zero failed and one optional external-file test skipped. This is source and Simulator evidence only; it does not validate physical-device capture, held-out tracker accuracy or tracer reliability.

## Immediate gate

1. Implement in-app Range recording and persistent local session library behaviour.
2. Implement Live Review rolling segments, fused detection, automatic post-roll replay and re-arm flow.
3. Collect consented long-session footage with labelled target-golfer real shots, practice swings, neighbouring golfers and range noise; validate accepted-shot precision and missed-shot rate on a physical iPhone, including 30 to 50-minute thermal and storage behaviour.
4. Validate the integrated zero-fee WASB-SBDT Core ML tracker on the held-out matrix, tune or fine-tune only if required, and connect its launch evidence to the target-golfer long-session gate. Do not claim production tracking or numerical distance before held-out and physical-device validation.
5. Continue the existing Watch hardware and release gates.

## Tracer incident diagnosed and replacement integrated on 24 August 2026

- A native probe against the supplied private sample reproduced Vision error 18, `No valid presentationTimeStamp`, on every frame. The service had passed a bare pixel buffer, misused `targetFrameTime` as media time, swallowed the errors and returned fixed coordinates.
- Passing each `CMSampleBuffer` preserved source presentation time and produced moving-shape observations. The existing geometric scorer then selected unrelated motion, including the club, confirming that generic trajectory detection is not golf-ball identification.
- The hard-coded inferred launch/apex/landing fallback is deleted. Inferred generic Vision geometry is non-displayable, unavailable candidates do not create editor defaults, and the player overlay is conditional on a verified tracer path.
- A third-party YOLO-family ONNX checkpoint was inspected and rejected because its embedded metadata declared AGPL and its detections on the private sample were mainly false or static.
- The official MIT-licensed NTT WASB-SBDT tennis weights were converted into a 2.6 MB Core ML package. Official and converted weight hashes, the MIT licence and an upstream notice ship with the app.
- Production one-shot analysis now evaluates three-frame heatmaps in overlapping 512 by 288 source-resolution tiles, suppresses duplicate peaks and requires a motion-consistent single-ball track. The renderer uses the observed point sequence and source timestamps rather than inventing a complete parabola.
- A signed Simulator probe against the private sample passed the exact Swift decoder, Core ML and linker path with 16 consecutive points from 2.018 to 2.518 seconds, moving from `(0.5606, 0.3422)` to `(0.5347, 0.2854)` and reaching `0.679` confidence. The temporary clip copies were deleted; the original Desktop file was untouched.
- The clean simulator suite contains 33 tests: 32 passed, zero failed and one optional external-file XCTest skipped. One clip and Simulator timing are not held-out accuracy or physical-device performance evidence.

## Validation completed on 19 July 2026

- XcodeGen is installed and `project.yml` is available as the project definition.
- Xcode lists the expected `Ronde Watch App` and `Ronde iOS` targets and schemes.
- The watch scheme built successfully for both a specific Apple Watch Ultra 3 simulator and the generic watchOS Simulator destination.
- The iOS companion scheme built successfully for the generic iOS Simulator destination.
- No automated test target exists, so no test pass is claimed.
- The current Git baseline is `823c10d`, where the Watch hardening release candidate is committed; the reviewer contract and configuration changes in this branch are not yet merged to `main`.

## Validation completed on 21 August 2026

- Both generic Watch and iOS simulator schemes built successfully.
- Seven focused iOS unit tests passed on an iPhone 17 Pro running iOS 26.0 Simulator.
- The iPhone reviewer vertical slice received a fresh visual pass.
- The iPad binary built and installed, but the fresh simulator remained on the launch placeholder; no iPad visual pass is claimed.
- No physical-device, rolling-capture, automatic replay, validated classifier or numerical-distance evidence exists.

## MVP usability reset validated on 21 August 2026

- Removed generic `VNDetectTrajectoriesRequest` output from shot-candidate and tracer decisions after it produced 26 false candidates for a one-swing clip.
- Added audio impact clustering with a four-second cooldown and a preferred-orientation-aware Vision body-motion fallback.
- The combined detector returned exactly one provisional body-motion candidate for the supplied 4K portrait, 30 fps, 6.62-second MOV in an escalated local harness. Its 5.352-second marker remains provisional and must be adjustable in review.
- Rebuilt single-shot review around the portrait-safe video hero, hidden candidate queue, compact Quick Review tools and persistent in-session assisted launch/apex/landing geometry.
- Added an iPhone/iPad AppIcon catalogue and a unique `Ronde Shot Review` product name while retaining `Ronde` as the on-device display name. App Store Connect record creation and upload still require direct portal evidence.
- Archived the generic iOS scheme successfully to `/tmp/RondeShotReview.xcarchive`; inspection confirmed the iPhone/iPad icon variants and embedded `Watch/Ronde.app`. The archive uses Apple Development signing, so this is packaging evidence rather than TestFlight upload evidence.
- Reconciled a 22 August physical-device install rejection: an Xcode-only edit had changed the generated iOS bundle identifier to case-mismatched `com.Ronde`. Regenerating from `project.yml` restored `com.ronde`, matching the embedded Watch app's `WKCompanionAppBundleIdentifier`. Physical reinstallation is the remaining direct-device check.
- Seventeen deterministic iOS tests passed on iPhone 17 Pro iOS 26.0 Simulator; the real external-file assertion was performed by the local harness because the XCTest host did not inherit the shell-only file path.

## Playback-first review validated on 22 August 2026

- Short single-shot imports now open directly into Shot Review after analysis; a zero-candidate short clip receives one adjustable fallback review moment instead of candidate-management UI.
- The complete estimated tracer is visible immediately over the main player and its launch, apex and landing remain adjustable.
- The single-shot surface contains Replay, Adjust path and collapsed timing correction only. Candidate queues, manual segmentation and shot/practice decisions remain in the multi-shot workflow.
- Vector, alignment and freehand annotation code and local annotation storage were removed.
- Seventeen iOS tests executed on iPhone 17 Pro iOS 26.0 Simulator with zero failures and one optional external-file probe skipped.
- Fresh deterministic portrait visual checks passed on iPhone 17 Pro and iPad Pro 11-inch simulators. These checks verify layout and visibility, not automatic ball tracking or physical-device behaviour.

## Source-time tracer execution recorded on 22 August 2026, superseded by the 24 August incident finding

- Fixed the dual-AAC import path by selecting the preferred stereo track and decoding float/int16/int32 PCM defensively. An escalated native AVFoundation probe returned exactly one audio candidate at 1.675 seconds for the supplied private sample, about 42 ms from the visually labelled 1.717-second impact and within two 30 fps source frames.
- Added a bounded, orientation-aware native Vision trajectory feasibility pass that consumes the uploaded file's own timestamps without requiring a specific FPS.
- The same sample appeared to produce zero defensible outbound points because the request had lost presentation timestamps. The 24 August probe invalidated that conclusion and exposed the fixed 0.18 fallback as fabricated geometry.
- The former down-the-line fallback was tuned against one sample and is now deleted.
- Replaced the static curve with an `AVPlayer` item-time tracer: hidden before impact, progressive during flight, held after completion and reset by replay/backward seek. Reduced Motion shows the complete curve at impact.
- Short single-shot review now autoplays once, retains one prominent Replay action and collapsed timing correction, and removes path adjustment from the primary surface.
- XcodeGen regeneration completed. Twenty-one simulator tests passed with zero failures and one external-file test skipped. A fresh simulator build succeeded.
- The supplied private clip was copied only into the iPhone 17 Pro simulator data container for a visual pass. The full estimated tracer and explicit provenance were visible over the actual video; no private footage entered the repository or app bundle.

## Real-shot decision pipeline validated on 23 August 2026

- Added explicit proposal, target-golfer evidence, golf-ball launch evidence, decision, clip-plan and tracer-eligibility types. Audio or body motion alone can no longer become a shot.
- A deterministic 300-second mixed-event scenario accepted exactly three verified target-golfer launches and produced source ranges 56–66, 172–182 and 291–300 seconds. Practice, duplicate, range-noise and different-golfer events did not enter the tracer rail.
- Long-session analysis, exact clip export and trajectory analysis enforce the same accepted-shot gate. The current production detector is deliberately unavailable, so real imports fail closed into the correction queue until validated model weights exist.
- A public YOLOv8 ONNX checkpoint was tested against the supplied private sample outside the repository and rejected for discontinuous, false-positive detections. No third-party model or footage was added to the app or repository.
- The combined iOS scheme built and 29 simulator tests completed on iPhone 17 Pro iOS 26.0: 28 passed, zero failed and one optional private-file probe was skipped.
- Sol's integration review found no P0 crash or data-loss issue. Its timestamp, non-target-association, misleading-copy and full-source Share findings were corrected before the final test pass.
