# Current State

**Reviewed:** 30 August 2026

**Release branch:** `main` contains the merged reviewer release candidate. The current short-shot-video refinement and local-first app redesign are uncommitted on `codex/redesignapp` and must not be described as shipped.

**Release-candidate scope:** independent watchOS shot-counter hardening plus the accepted universal iPhone/iPad Shot Reviewer expansion.

## Stage

Ronde is in pre-release product hardening and reviewer validation. The core Watch round flow and its reliability work remain unchanged. The current iPhone/iPad working tree adds an Apple-only entry and a complete Home, Library, Profile and individual-review shell around the one-video MVP. Reviews persist in an account-scoped local archive; raw video and analysis stay on device, while the live Supabase schema accepts only private profile and lightweight library metadata. Timestamp-based acquire-and-track ball analysis may seed a perspective-aware estimate from impact through a marked apex to landing. Detector-attributed geometry is a causal solid-purple trail held just behind the source-timed ball position; fitted geometry is dashed purple and appears only after the observed trail. Supported fits show `Model carry` with `Estimate · uncalibrated`. Unsupported clips still fail closed with `Ball flight not tracked`. The Supabase Apple provider is enabled for native client ID `com.ronde`; the Apple Developer App ID capability and signed-device login remain unverified, so live native login is not yet proven. Long-session slicing and hands-free review foundations are dormant. One owner-supplied rendered output has been inspected; held-out footage accuracy, representative output review, physical-device performance and distribution remain open gates.

## Capability status

| Capability | Status | Current truth |
| --- | --- | --- |
| watchOS product | Implemented | Standalone watchOS 10+ SwiftUI app; it remains the independent core shot counter. |
| iPhone/iPad reviewer contract | Accepted | Universal light-theme, local-first reviewer narrowed to one shot video up to 60 seconds, with an Apple-only account boundary and no raw-media upload. Long-session and live workflows are dormant. See ADRs 0008 and 0009. |
| iPhone/iPad reviewer | Implemented in current working tree | Home, Library and Profile use a Caddie-led shell with Flightline-style real metrics and charts. Photos/Files import, account-scoped persistence, favourites, optional place/course, club and notes, full-source playback, evidence editing, manual rescue and traced-video export/share are connected. Unsupported clips fail closed. |
| Sign in with Apple | Source and Supabase provider configured; device gate open | The iOS entitlement, secure nonce flow, native Apple credential exchange and session restoration compile. The hosted Supabase provider is enabled for `com.ronde`. The Apple Developer App ID capability and signed-device login remain unverified. |
| Supabase account metadata | Hosted schema implemented | `profiles` and `library_items` are live with per-user row-level security and anonymous grants revoked. Only lightweight labels and provenance sync; raw media, local paths and analysis stay on device. Remote metadata restoration is not yet implemented. |
| Live Review automatic loop | Missing | In-app Range recording, rolling segment writer, fused hands-free detection, automatic post-roll replay and temporary-buffer cleanup are not implemented. |
| Automatic tracer quality | Functional; release validation open | The tracker decodes sequentially by source presentation timestamp, samples at a 30 Hz analysis cadence, lets competing full-frame paths establish a launch before local-ROI tracking, trims early detector hand-offs and reports cost instrumentation. Playback and export map those timestamps to cumulative path distance, keep the solid observed stroke behind the ball, and defer dashed model geometry until observation ends. A passing track may seed estimated launch, apex, landing and broad carry. One corrected exact output has been inspected; the prior three-positive regression and this single rendered positive remain too small, and representative positive/negative evidence is still missing. |
| Round setup | Implemented | Quick 9, Quick 18, manual par and bundled Sydney course selection exist. |
| Shot counting | Implemented | Add, undo and hole transitions exist; Action Button uses App Intents. |
| Local history | Implemented in release candidate | SwiftData stores rounds and hole scores, with recovery and degraded storage modes. |
| Workout session | Implemented in release candidate | HealthKit golf workout supports long-running rounds, recovery and safer ending. |
| Location and walking | Implemented foundation | Nearby-course detection and pedometer support exist; permission and real-device behaviour need validation. |
| Preview routing | Implemented in current working tree | `RONDE_PREVIEW_SCREEN` supports deterministic sign-in, Home, Library, Profile, media-detail and quick-review routes. |
| Automated tests | Verified 30 August 2026 | `Ronde iOS AppTests` covers account-scoped archive isolation, honest dashboard metrics, impact clustering/cooldown, body motion, clip windows, local media, orientation, evidence-anchored completion, manual provenance, explicit Range opt-in, capture stability, causal source-time tracer reveal/reset, real-shot gating and selector invariance at 25/30/50/60/120/240 fps. The final run executed 62 checks: 60 passed, two optional external probes skipped and zero failed. |
| Simulator build | Verified 30 August 2026 | The generic iOS Simulator scheme, embedded Watch app, Core ML package and generated project build successfully. |
| iPhone visual review | Verified 30 August 2026 | Fresh iPhone 17 Pro iOS 26.5 passes covered Apple-only sign-in, Home, Library, Profile and the individual video-first review/edit route. Native Liquid Glass navigation, solid/dashed provenance and labelled import actions are visible. This is layout evidence, not detector or live-auth evidence. |
| iPad visual review | Verified 30 August 2026 | Fresh iPad Pro 11-inch iOS 26.5 Home review passed for the centred adaptive canvas, chart hierarchy, system glass navigation and labelled import action without clipping. |
| Hardware validation | Unverified | Action Button, HealthKit recovery and outdoor legibility need a real Apple Watch pass. |
| Distribution packaging | Archive verified 21 August 2026 | A generic-device archive completed successfully with compiled iPhone/iPad icons and the embedded Watch app. It is development-signed; App Store Connect record selection, distribution signing, upload and TestFlight availability remain unverified. |

## Current risks

- The reviewer release candidate is merged into `main`, but merging does not replace the remaining physical-device, held-out footage, signing or distribution gates.
- Watch scoring, persistence and workout state transitions still have no dedicated automated test target.
- Simulator success cannot prove Action Button or HealthKit behaviour on hardware.
- Location, HealthKit and motion data increase privacy and permission-copy obligations.
- Xcode project changes and `project.yml` must remain synchronised.
- The measured per-tile allocation runaway is corrected locally, but the remaining roughly 235 to 699 MB macOS diagnostic footprints are not physical-iPhone evidence. Long video processing, temporary rolling capture and on-device models may still expose memory, battery, thermal and storage limits.
- The integrated tracker passes three private positive originals across daylight/night, landscape/portrait and H.264/HEVC. This remains too small and has no negative clips, so it may still miss other balls or falsely follow clutter. Release requires representative positives and negatives.
- Long-session code remains in source but is dormant. If re-exposed, its fixed-camera associator still cannot perform general multi-golfer identity tracking.
- The completed automatic path is a perspective presentation estimate anchored to observed ball evidence. Its carry range is broad and uncalibrated; it is not measured distance, physical apex height or an observed full flight.
- The current iOS 26.5 Simulator exits inside Apple's Core Animation IOSurface renderer when an exporter integration test performs video composition. The same production exporter completed the exact 4K source in a macOS harness. Neither result replaces a signed physical-iPhone export test.
- Native Apple login cannot be claimed complete until the Apple Developer App ID has the capability and a signed physical-device test passes first sign-in, repeat sign-in, restoration and sign-out.
- Remote metadata is currently one-way device-to-Supabase sync. Reinstall or a second device cannot reconstruct a missing local video, trace or archive from those rows.

## Delivery validation refreshed on 30 August 2026

- Regenerated `Ronde.xcodeproj` from `project.yml` and built the `Ronde iOS` scheme for the generic iOS Simulator. The embedded Watch app, universal AppIcon, motion permission copy and packaged Core ML model all compiled successfully.
- Ran the clean `Ronde iOS` suite on an iPhone 17 Pro running iOS 26.0 Simulator after the memory correction: 52 checks executed, 50 passed, two optional external-video/audio probes skipped and zero failed.
- Re-ran the exact macOS production-code diagnostics without changing the selected paths. Landscape A reached a 235 MB peak footprint, Landscape B 699 MB and Portrait C 678 MB; Landscape B previously reached 19.19 GB because it allocated a 5.3 MB input tensor for every one of its 3,217 tile predictions.
- Re-ran the optional exact-production external matrix after the memory correction with temporary copies of all three private originals: one matrix test passed, zero skipped and zero failed in 1,397.075 seconds. The clips remained outside Git; the temporary copies and opt-in scheme setting were removed after testing.
- Ran the supplied Landscape A original through the exact decoder, packaged model and selector in a bounded two-tile diagnostic corridor, then through the current perspective completion and exporter. It selected 11 observed points at `0.417` confidence, fitted a bounded landing near `(0.470, 0.508)`, presented `95–155 m` model carry and rendered the 3,840 x 2,160 source as 190 frames at 30 fps. Full-resolution frame inspection confirmed the ball remains visibly ahead of the solid causal trail, while the dashed connector/continuation, `EST. APEX` and uncalibrated carry badges appear only after the observed span. The bounded corridor does not prove production acquisition recall or distance accuracy.
- Ran the clean complete iOS 26.5 Simulator suite after clearing the private diagnostic path: 53 checks executed, 51 passed, two optional external-video/audio probes skipped and zero failed. The evidence-anchored flight suite contributed eight passing checks, including the 60-second import boundary and launch-displacement guard.
- Added the Caddie-led app shell with Flightline-style evidence metrics, Apple-only entry, account-scoped local review persistence, media search/favourites/details, native iOS 26 glass navigation and a material fallback. No floating plus action is present.
- Applied the private Supabase profile/library schema and anonymous-grant restriction migrations to project `apaowuzliauwxbxylfpk`; both hosted tables have row-level security enabled.
- Verified in the authenticated Supabase dashboard that Apple Auth is enabled and its saved native Client IDs value is `com.ronde`; no OAuth secret is configured for this native-only flow.
- Completed fresh iPhone 17 Pro and iPad Pro 11-inch iOS 26.5 visual passes for the redesign. The login, dashboard, chart, library, profile and media-detail evidence are fixture/layout checks only.
- Ran the final complete `Ronde iOS` suite on iPhone 17 Pro iOS 26.5 Simulator: 62 checks executed, 60 passed, two optional external-video/audio probes skipped and zero failed. Result bundle: `/tmp/ronde-final-derived/Logs/Test/Test-Ronde iOS-2026.08.30_17-26-36-+1000.xcresult`.
- This is source and Simulator evidence only. It does not validate physical-device latency, memory, thermal behaviour or held-out accuracy.

## Immediate gate

1. Enable Sign in with Apple for the `com.ronde` App ID in the Apple Developer portal, then validate new sign-in, repeat sign-in, restoration and sign-out on a signed physical iPhone against the already-enabled Supabase provider.
2. Run the documented 20 to 30 clip validation matrix, reporting acquisition recall, false-tracer rate, target association and per-clip cost separately.
3. Validate the current tracker and 60 fps capture-quality foundation on physical iPhones, including latency, memory, battery, thermal and storage behaviour over 30 to 50 minutes.
4. Inspect the current purple launch/apex/landing treatment and carry range across exported positive clips, plus local archive restoration and RLS metadata ownership across two test accounts.
5. Fine-tune only if the matrix proves it necessary and a licensed, consented golf dataset and reproducible training path exist. Do not claim training support from the upstream WASB repository while its training instructions remain unavailable.
6. Keep precise carry and physical apex height unavailable until calibrated, known-ground-truth evidence exists, and continue the existing Watch hardware and release gates.

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
- At that validation time, the Git baseline was `823c10d`, where the Watch hardening release candidate was committed; the reviewer contract and configuration changes had not yet merged to `main`.

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
