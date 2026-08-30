# Context Changelog

## 30 August 2026

### Delivery

- Merged the evidence-backed iOS Shot Reviewer release candidate into `main` through PR #3. The automatic context refresh followed the merge. Physical-device performance, held-out footage, signing and distribution remain separate open gates.

### Physical-device memory-pressure correction

- Reproduced the One Shot termination as an unbounded inference-allocation problem: the tracker created a new 5.3 MB `MLMultiArray` for every tile prediction. The supplied Landscape B clip evaluated 3,217 tiles and reached a measured 19.19 GB peak process footprint in the macOS production-code diagnostic, which would exceed an iPhone's memory budget.
- Changed tiled inference to allocate and refill one input tensor per analysed three-frame model window, drain Core ML's Objective-C prediction temporaries after every tile and keep per-tile cancellation. Progress now advances about four times per model window without flooding the main actor.
- Kept the selected paths unchanged while reducing Landscape B's measured peak footprint from 19.19 GB to 699 MB and maximum resident memory from 13.96 GB to 1.04 GB. Landscape A and Portrait C peaked at 235 MB and 678 MB respectively in the same local diagnostic.
- Made Vision body-pose analysis a true fallback when audio finds no usable impact candidate, avoiding a second full video decode for the common audio-backed One Shot path. Replaced the ambiguous analysis message with distinct `Finding impact` and `Tracking the ball` stages.
- Added deterministic fallback-policy coverage. The clean iOS Simulator suite now contains 52 checks: 50 passed, two optional external-video/audio probes skipped and zero failed. Physical-iPhone confirmation remains required before declaring the termination resolved on hardware.
- Re-ran the opt-in three-video matrix through the corrected exact iOS production path on iPhone 17 Pro iOS 26.0 Simulator: one matrix test passed, zero skipped and zero failed in 1,397.075 seconds. All temporary private-video copies and the opt-in scheme setting were removed afterwards.

### Real-video false-acquisition correction

- Reproduced an intermittent wrong tracer in the exact iOS Core ML path: the overlay coordinates were correct, but the tracker could narrow around the first coherent high-confidence moving speck before the ball became visible.
- Changed post-impact acquisition so alternate full-frame paths compete through the launch window and eight linked observations are required before local-ROI tracking begins or any later shortened path may be displayed. Full-frame acquisition is evaluated every other sampled window to bound the added inference cost.
- Added post-selection detector hand-off trimming so early club/body motion cannot be labelled as observed ball flight when the model later joins the real ball.
- Added an optional external-video regression matrix plus a deterministic club/body-to-ball hand-off test. Private originals remain outside the repository.
- Passed all three owner-supplied positive originals through the exact production tracker on macOS and iPhone 17 Pro iOS 26.0 Simulator. The final observed results were 7, 86 and 82 points respectively; the portrait path begins at the visible ball rather than through the golfer.
- The false-acquisition exact-code three-video Simulator matrix passed in 1,290.760 seconds before the later memory-pressure correction. Physical-iPhone latency, memory and thermal behaviour remain open gates.

## 29 August 2026

### Evidence-anchored tracer and reviewer product reset

- Replaced nominal-frame assumptions with sequential source-PTS decoding and a timestamp-based 30 Hz analysis cadence that accepts 25, 30, 50, 60, 120 and 240 fps sources without changing time windows.
- Reworked the model loop into full-frame acquisition/reacquisition plus predicted local-ROI tracking, with a four-second analysis cap and instrumentation for decoded, skipped and sampled frames, model windows, tiles, search modes, candidates and selected points.
- Removed the short-clip 52%-of-duration impact guess. One Shot timing now prefers impact audio, falls back to observed body motion for silent clips and lets the ball tracker acquire from that source time; clips with neither signal require a manual marker.
- Added a complete consumer tracer only after a real observed launch passes the ball-specific gate. The observed line is solid; the bounded screen-space continuation is dashed and labelled `Observed launch · estimated flight`. Unsupported footage still receives no automatic curve.
- Added labelled manual tracer rescue/editing, restored automatic geometry after clearing a manual edit, and connected local MOV rendering plus native sharing to the exact reviewed geometry without rerunning detection. Export preserves common source cadences from 24 through 240 fps rather than forcing every derivative to 30 fps.
- Added an opt-in fixed-camera single-golfer Range adapter. Automatic Range acceptance requires explicit confirmation of a fixed camera, selected target golfer and no other golfer in frame; it otherwise fails closed.
- Rebuilt the reviewer hierarchy and visual system across iPhone and iPad with compact typography, a dominant One Shot path, secondary Range workflow, video-led review, restrained controls, clearer provenance and Dynamic Type, accessibility and Reduced Motion support.
- Strengthened live-capture readiness with a 60 fps target, focus/exposure/white-balance settlement and locking where supported, Core Motion stability classification and actionable framing guidance. The rolling writer and automatic replay loop remain separate open work.
- Added deterministic tests for evidence-anchored flight completion, provenance, manual rescue, Range opt-in, capture stability and selector invariance across common presentation rates. Representative footage accuracy and physical-device performance remain release gates in `TRACER_VALIDATION.md`.
- The complete iPhone 17 Pro iOS 26.5 Simulator run executed 47 checks: 46 passed, one optional external-file probe was skipped and zero failed.
- Completed fresh deterministic visual passes on iPhone 17 Pro iOS 26.0 and iPad Pro 11-inch iOS 17.5 Simulators. The passes verified the current solid/dashed treatment, compact control hierarchy and adaptive two-column layout; they do not prove real-video detection accuracy.
- Recorded ADR 0007. Numerical carry distance and apex height remain unavailable without calibrated ground truth.

### Reviewer delivery validation

- Regenerated the checked-in Xcode project from `project.yml` and built the `Ronde iOS` scheme for the generic iOS Simulator. The universal reviewer, embedded Watch app, AppIcon and packaged Core ML model compiled successfully.
- Re-ran the focused iOS suite on an iPhone 17 Pro running iOS 26.0 Simulator: 32 passed, zero failed and one optional external-file XCTest skipped. This is not physical-device or held-out tracer-quality evidence.

## 24 August 2026

### Replace fabricated tracer with free evidence-backed Core ML tracking

- Found the direct cause of identical tracers across different uploads: the trajectory service passed a `CVPixelBuffer` to Vision, discarded the sample presentation timestamp, misused `targetFrameTime` as media time, swallowed Vision error 18 for every frame and then returned one hard-coded launch/apex/landing fallback.
- Changed the stateful Vision request to consume each `CMSampleBuffer` with its presentation timestamp and left `targetFrameTime` at its documented default processing policy.
- Deleted the hard-coded inferred fallback. A candidate is now tracer-available only when observed ball-specific points satisfy the display gate; otherwise the review says `Ball flight not tracked` and draws nothing.
- Prevented the review view and in-session editor state from silently creating or persisting default tracer geometry for unavailable candidates.
- Rejected a third-party YOLO-family ONNX checkpoint after local inspection found AGPL metadata and private-sample evaluation produced mainly false or static detections. No model, training data or private footage entered the repository.
- Integrated the official MIT-licensed NTT WASB-SBDT three-frame sports-ball model as a 2.6 MB Core ML package. The official PyTorch download and converted Core ML package have matching verified weight provenance, and the upstream licence and hashes ship with the app.
- Added overlapping 512 by 288 source-resolution tile inference, peak suppression and a single-ball temporal linker requiring at least seven consecutive, directionally stable post-impact detections. ByteTrack is unnecessary for this single-object lane and SAM-style models remain offline labelling aids only.
- Changed the overlay to render the model's actual detected points using their source presentation timestamps. It no longer expands three points into an invented apex and landing arc.
- A signed iOS Simulator probe against the private 6.618-second sample tracked 16 consecutive points from 2.018 to 2.518 seconds, moving from `(0.5606, 0.3422)` to `(0.5347, 0.2854)` with peak confidence `0.679`. The temporary signed test copy was removed afterwards and no private footage remains in the repository or Simulator.
- Added deterministic track-linking and fail-closed tests. The clean final simulator suite contains 33 tests: 32 passed, zero failed and one optional external-file XCTest skipped. Physical-device latency and held-out false-tracer validation remain release gates.

## 23 August 2026

### Real-shot gate and video-first range review

- Replaced candidate-first long-session behaviour with an evidence-gated pipeline: raw audio/body-motion events are proposals only; an automatic shot requires target-golfer swing/impact evidence plus a stable, time-aligned golf-ball-specific launch attributed to that golfer.
- Separated accepted shots, uncertain moments and rejected events. Only accepted shots receive a clamped impact -5/+5 clip plan and tracer eligibility; uncertain moments remain in a collapsed correction queue without tracers, while generic motion, background events and different-golfer events are rejected from the primary flow.
- Added policy-gated automatic clip export and trajectory-analysis entry points so downstream code cannot accidentally process an uncertain event as a shot.
- Rebuilt the review hierarchy around the video: short clips autoplay into direct tracer review; long sessions show a compact real-shot filmstrip, with practice/uncertain review secondary and collapsed.
- Connected the explicit One Shot and Range Session choices to import and analysis. Duration no longer silently switches workflows, so a short multi-shot burst still receives strict segmentation and a long setup around one swing still receives direct review.
- Added independent target-golfer association and golf-ball launch detector adapters with model-unavailable defaults. Validated target impact is now the canonical clip/playback/tracer timestamp; explicit non-target launches are rejected while unresolved ownership remains uncertain.
- Removed Range copy that implied production detection was already complete. Removed the visible tracer-adjustment and Share actions so the primary review remains video plus Replay until Ronde can generate an accurate path and export the accepted clip with its rendered tracer.
- Refined the light visual system towards warm porcelain, deep pine, eucalyptus and restrained tracer gold, with quieter radii, shadows, typography and icon-led actions across iPhone and iPad layouts.
- Evaluated a public YOLOv8 golf-ball ONNX checkpoint against all 199 frames of the supplied private sample outside the repository. Its detections were discontinuous and included obvious false positives, so the weights were rejected and not integrated.
- Added deterministic coverage for a 300-second session containing exactly three verified target-golfer shots alongside a practice swing, an impact-like noise event, a duplicate proposal and a different golfer. The policy accepted exactly three shots, produced boundary-clamped clip plans and denied tracers to every uncertain or rejected event.
- Ran 29 iOS simulator tests: 28 passed, zero failed and one optional private-file probe was skipped. Automatic production acceptance remains fail-closed until a licensed detector passes held-out positive and negative footage.

## 22 August 2026

### Source-time tracer execution

- Replaced the static assisted overlay with an `AVPlayer` item-time-synchronised tracer that remains hidden before impact, progressively reveals from launch to landing, holds after completion and resets after replay or backward seeking.
- Added Reduced Motion behaviour that reveals the complete path at impact without progressive animation.
- Fixed imported-audio impact analysis to select the stereo AAC track when available and decode float, 16-bit or 32-bit PCM defensively. The supplied private clip produced one native audio candidate at 1.675 seconds, within two 30 fps source frames of the visually labelled 1.717-second strike.
- Added a bounded, orientation-aware native Vision trajectory feasibility service. It accepts every uploaded frame rate and uses source timestamps, but generic motion remains labelled inferred and cannot earn an observed-ball claim.
- Ran the native baseline against the supplied 6.618-second portrait sample: zero defensible outbound points were found, so the app correctly retained an estimated path rather than fabricating tracked flight.
- Refined the fixed-tripod fallback geometry so its launch begins at the down-the-line hitting position rather than over the golfer; model-backed launch anchoring remains a later detector task.
- Simplified one-shot review to automatic playback, one prominent Replay control and collapsed timing correction. Removed tracer/path adjustment from the primary interface and made the provenance label explicit.
- Regenerated the Xcode project, passed 21 simulator tests with zero failures and one external-file test skipped, completed a clean simulator build, and visually checked the real sample in the iPhone 17 Pro simulator with its full estimated tracer over the video.

### Playback-first Shot Review

- Changed short one-swing imports to navigate directly from import into Shot Review, with the estimated tracer visible over the main player by default.
- Reserved candidate queues, shot/practice decisions, manual markers and the extra timeline for multi-shot recordings.
- Reduced the single-shot controls to Replay, Adjust path and a collapsed timing correction. The later source-time execution above removes Adjust path from the primary surface.
- Removed vector, alignment and freehand annotation UI, models, local storage and tests from the reviewer scope.
- Reworked the tracer into a brighter ground-to-apex-to-landing treatment and retained adjustable normalised launch/apex/landing geometry.
- Added adaptive phone and iPad review layouts, including a bounded portrait playback stage that shows the full frame without pushing primary controls off-screen.
- Regenerated the project, passed 17 iOS tests with one optional external-file probe skipped, and completed fresh deterministic portrait visual checks on iPhone 17 Pro and iPad Pro 11-inch simulators.

## 21 August 2026

### Universal Shot Reviewer boundary

- Accepted a universal light-theme iPhone/iPad Shot Reviewer alongside the independent Watch shot counter.
- Added Range Session and hands-free Live Review concepts with bounded temporary capture, impact -5/+5 editable clips and recoverable shot/practice/uncertain candidates.
- Added fixed, normalised-coordinate annotations and a confidence-gated 2D tracer boundary. Numerical distance remains deferred until calibration and ground-truth validation.
- Declared reviewer media and model processing local-only for MVP, with camera, microphone, photo import and add-only export usage strings in `project.yml`.
- Physical-device capture, long-session performance, model quality and tracer reliability remain unverified.

### Reviewer vertical slice validation

- Implemented and reviewed local Photos/Files import, metadata probing, provisional Vision trajectory candidates, manual markers, logical impact -5/+5 playback, screen-space tracer overlay, fixed annotations and live camera preview/state foundations.
- Added seven focused iOS unit tests; all passed on an iPhone 17 Pro running iOS 26.0 Simulator.
- Built both generic simulator schemes and completed an iPhone visual pass.
- Built and installed the iPad binary, but the fresh simulator remained on the launch placeholder; no iPad visual pass is claimed.
- In-app Range recording, rolling segment capture, fused hands-free detection, automatic post-roll replay, persistent session library, validated real/practice classification, physical-device evidence and numerical distance remain open.

### Reviewer visual system refinement

- Moved the reviewer visual system from generic productivity styling towards quiet-luxury golf: warm chalk and stone surfaces, moss, sage and eucalyptus accents, restrained serif display typography, and quieter cards, tags and buttons.
- Preserved the light-only adaptive and accessibility direction. This records the intended visual system and does not add an iPad or physical-device validation claim.
- Restored restrained mode iconography, added an accessibility-hidden fairway/ball-flight motif, normalised home cards to full-column width and added compact-width adaptive action stacks; focused visual checks covered iPhone 17 Pro and iPhone SE (3rd generation) simulators only, with no new iPad or device claim.

### Reviewer usability reset

- Replaced generic Vision-trajectory candidates with clustered impact audio and a preferred-orientation-aware Vision human-body-motion fallback. Automatic outputs remain uncertain review markers with a four-second cooldown.
- Verified the combined detector returns one provisional candidate for the supplied private 4K portrait, 30 fps, 6.62-second one-swing MOV. The source remained outside the repository.
- Made portrait video the Quick Review hero, hid the candidate queue for one-shot clips and removed the extra-marker action from short single-candidate reviews.
- Added an editable assisted launch/apex/landing arc with normalised in-session geometry and explicit manual/no-distance language. Generic trajectories no longer claim tracer availability.
- Added a universal iOS AppIcon, retained `Ronde` as the device display name and changed the App Store product name to `Ronde Shot Review` to avoid automatic app-record name collision.
- Regenerated the Xcode project and passed 17 deterministic iOS tests on iPhone 17 Pro iOS 26.0 Simulator. The external-file XCTest remained skipped; the supplied clip was validated separately with the same combined detector in a local harness.
- Completed a generic-device iOS archive and verified its compiled iPhone/iPad icons and embedded Watch app. The archive is development-signed; App Store Connect upload and TestFlight availability remain separate external gates.
- Repaired a physical-device installation blocker by regenerating the Xcode project from `project.yml`: the generated iOS bundle ID is again `com.ronde`, matching the Watch app's companion identifier. Xcode target bundle identifiers must be changed through `project.yml`, never as a generated-project-only edit.

Git remains the exact commit-by-commit record. This file records material product, architecture, privacy and release changes.

## 19 July 2026

### Cross-tool context library

- Established repository entry points for agents, Claude, Gemini, Copilot and people.
- Added the product contract, current-state reconciliation, architecture, roadmap, operations, decision log and complete Git ledger.
- Recorded the app-hardening boundary before preparing the implementation as a separate release candidate.
- Replaced the duplicated Claude summary with a canonical `AGENTS.md` import.
- Verified both shared schemes build for their generic simulator platforms; no test target exists.

### Watch hardening release candidate

- Persistence recovery and degraded storage behaviour.
- HealthKit workout recovery and safer end-state handling.
- Action Button intent donation and shot-routing changes.
- Debug preview routing and a broad watch visual refinement.

These implementation changes are included in the current release candidate. Merge, real-device and distribution status remain separate evidence gates.
