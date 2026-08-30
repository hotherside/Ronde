# Context Changelog

## 30 August 2026

### Source-cadence recall correction and search-scale rejections

- Recorded the signed-iPhone TestFlight field result across five owner-selected shot videos: only one video produced an automatic tracer, and that tracer was not visually accurate. The exact five sources have not yet been transferred into the labelled external matrix, so this is decisive product feedback but not per-clip detector diagnosis.
- Corrected `PresentationTimestampFrameSampler` so a real source frame arriving up to 2 ms before the nominal 30 Hz target remains eligible. A measured 30.087 fps stream now retains all 31 test frames instead of collapsing to every second frame, while 50, 60, 120 and 240 fps sources remain bounded near the 30 Hz analysis cadence.
- Evaluated a denser acquisition experiment that ran the current WASB tennis model on every accepted three-frame window. The full-frame Landscape A production probe completed in 265.965 seconds on CPU-only Simulator inference but selected the wrong moving object: its launch `y` was `0.3903`, outside the labelled `0.20...0.30` mid-air corridor. The dense experiment was rejected and the alternate-window false-acquisition guard was restored.
- Evaluated a 2x predicted-position crop after competitive ball acquisition, while keeping acquisition and reacquisition at native source scale. The exact three-video matrix passed in 992.403 seconds, but observed-point counts remained unchanged at 7, 86 and 82 and launch coordinates were effectively unchanged. The crop added model work without measured tracking extension, so it was removed rather than shipped as an unproven accuracy improvement.
- Tightened the optional private-matrix regression from a generic five-point floor to the established per-clip baselines of 7, 86 and 82 points, while retaining each labelled launch corridor and rising-flight check.
- Passed the focused `GolfBallTrackSelectorTests` suite on iPhone 17 Pro iOS 26.0 Simulator after removing the rejected experiment. The private fixture link and temporary external-test enablement were removed; no private footage entered Git.

### Local-first iPhone/iPad app redesign

- Brought the Caddie prototype hierarchy into the native app: golf-led Apple-only entry, personalised Home, real video thumbnails, an overlaid Library grid, Profile scorecard and places, plus Flightline-style trace-rate and activity charts. The primary import control is now a labelled `Add video` Photos action; the obsolete download-style affordance and floating-action pattern are absent.
- Rebuilt individual review as an edge-to-edge, video-first route with restrained glass back/favourite/edit chrome, a single evidence strip and concise provenance copy. Automatic carry/provenance cards no longer compete with the route controls inside the video.
- Moved manual tracer placement into a dedicated full-screen editor. Impact, Apex and Landing are direct-manipulation handles over the fitted source frame with point selection, frame stepping, Undo and Reset in a dark Liquid Glass dock. Cancel discards the draft; Save persists separately labelled user-authored geometry without changing automatic observed evidence.
- Revalidated the final adaptive build on iPhone 17 Pro and iPad Pro 11-inch iOS 26.5 Simulators. The complete working-tree suite passed with two optional external-media probes skipped and zero failures; the screenshots remain layout evidence rather than signed-device, live-auth or real-footage accuracy evidence.
- Replaced the reviewer-only entry with an Apple-only sign-in screen and a complete Home, Library and Profile shell. The Caddie-led hierarchy uses horizontal media tiles and the Flightline direction for evidence metrics and eight-week charts.
- Adopted native iOS 26 Liquid Glass for structural tab and toolbar navigation with a restrained system-material fallback on earlier supported iOS versions. Import is a labelled toolbar or empty-state action; no floating plus action is present.
- Added an account-scoped local review archive with atomic complete-file-protection writes. Reviews now retain favourites, optional place/course, club, notes and evidence geometry across relaunches without exposing one Apple account's library to another on the same device.
- Added individual media detail and edit interactions around the existing video-first workspace: favourite, edit metadata, adjust impact timing, inspect trace provenance and rough carry, adjust/manual trace, export and delete local plus hosted metadata.
- Integrated Supabase Swift 2.55.1, secure native Apple nonce exchange, session restoration and best-effort lightweight library metadata sync. Raw videos, file paths, tracer geometry and analysis stay on device.
- Applied hosted `profiles` and `library_items` migrations to Supabase project `apaowuzliauwxbxylfpk`, enabled per-user row-level security and revoked anonymous table access. Verified the saved Apple Auth provider as enabled for native Client IDs value `com.ronde` with no OAuth secret; Apple Developer capability and signed-device login remain unverified.
- Added deterministic archive-isolation and honest-metrics coverage. The final complete iPhone 17 Pro iOS 26.5 Simulator suite executed 62 checks: 60 passed, two optional external-video/audio probes skipped and zero failed. Fresh iPhone 17 Pro and iPad Pro 11-inch iOS 26.5 visual passes covered sign-in, Home, Library, Profile and the media-detail design; these remain Simulator fixture evidence.
- Added ADR 0009 for the local-first account, persistence and private metadata boundary.

### Short-shot-video MVP and impact-timed tracer completion

- Narrowed the exposed reviewer MVP to one Shot Video import up to 60 seconds. The full source is retained for review; Range Session slicing, candidate acknowledgement and Live Review remain dormant implementation foundations.
- Diagnosed the supplied Codex export: it contained only a seven-point mid-air fragment, started reveal at the first observed point, projected only forwards for a short bounded interval and exported the approximately 30 fps source at 16.67 fps.
- Replaced point-count and separately ordered segment reveals with a shared `FullFlightRevealTimeline` for playback and export. It assigns monotonic model times around the preserved detector timestamps, smooths the combined launch-observation-continuation sequence once and maps media time to cumulative path distance.
- Added a separate fail-closed launch-anchor detector over the source frames around impact. It selects one compact bright object that disappears into the accepted trajectory corridor only when that candidate is uniquely stronger than competing objects; it cannot make an unsupported clip tracer-eligible.
- Replaced the rejected dashed and late bulk-reveal treatment with one smoothly tapered solid-purple broadcast ribbon. Estimated launch and continuation ranges use subtly lower opacity, the observed range retains a small sampling-derived gap behind the visible ball, and no provenance boundary creates a seam or separate drawing order. `EST. APEX` appears when reached; `MODEL CARRY` and `ESTIMATE · UNCALIBRATED` appear at landing.
- Replaced the first-observation time origin with an impact-time perspective flight fit. The detector-attributed points remain unchanged; separate estimated geometry now connects towards impact and continues through a marked image-space apex to a bounded landing. Estimated launch displacement and all eligible endpoints remain inside a safe presentation area.
- Added a broad metres carry range from similarly plausible fits. Screen rate now selects only a broad full-shot versus chip-like speed/elevation prior, while a separate gentler down-range drag assumption avoids reusing the strong screen-perspective damping as physical carry loss. It remains labelled `MODEL CARRY` and `ESTIMATE · UNCALIBRATED`, not a measured-distance or launch-monitor claim.
- Export uses the same cumulative-distance keyframes and tapered solid-purple ribbon as playback. Export badges rasterise text through Core Text so carry, provenance, `EST. APEX` and `EST. LANDING` labels survive AVFoundation composition. Uniform whole-continuation compression is superseded: original model time plus the sampling-derived lag, capped at 50 ms, is preserved through apex; only post-apex descent may compress, the completed-path hold is capped at 120 ms, and sources too short for apex plus lag withhold landing/carry.
- The detector/model join residual now decays to zero with `(1 - progress)²`; lateral landing displacement follows the robust observed direction and blends with smoothstep inside a padded down-range corridor. Observed detector points, model weights and carry calculation are unchanged.
- Preserved common source cadence and corrected orientation transforms in traced MOV export. The real-source exact-code probe against `IMG_0495.mov` selected the same 11 observed points and anchored the start around `(0.524, 0.752)`. It added a 16-point launch connector and 250-point continuation, placed the estimated apex at `(0.515, 0.122)` and landing at `(0.488, 0.494)`, showed the existing `150–220 m` model carry and rendered 190 frames at 30 fps. It exercises source-time, ordering and bounded-corridor invariants. The owner subsequently rejected the visual flight and landing output as still off, so this checkpoint makes no accepted accuracy, landing or distance claim.
- The focused selector and evidence-anchored suites pass 32 checks with zero failures and one optional external-matrix skip, including unique/ambiguous launch-anchor gating, exact anchor start, chronological range ordering, exact joins, monotonic visibility, source-time interpolation, no-future-observation gating, short-source completion, Reduced Motion and playback/export keyframe equivalence. A macOS exact-source harness completed the current 4K Core Animation export. The iOS 26.5 Simulator's video compositor exits with an IOSurface/XPC API-misuse trap during exporter integration, so physical-iPhone export remains a separate gate.
- Passed the final complete iOS 26.5 Simulator suite with the chronological solid-purple ribbon: 66 checks executed, 64 passed, two optional external probes skipped and zero failed. The build included the embedded Watch app and packaged model. The real-source model probe used a bounded two-tile diagnostic corridor, so it verifies completion/export inputs after acquisition rather than general full-frame recall; the corrected ribbon was also inspected in the exact 4K re-export.
- Passed the final complete iPhone 17 Pro iOS 26.0 Simulator suite after launch anchoring and short-source completion: 71 checks executed, 69 passed, two optional external-media probes skipped and zero failed.
- Re-ran the complete iPhone 17 Pro iOS 26.0 Simulator suite before checkpoint delivery: 74 checks executed, 72 passed, two optional external-media probes skipped and zero failed. This validates deterministic implementation behaviour, not accepted visual flight, landing or carry accuracy.
- Added ADR 0008 for the short-shot-video boundary, estimated launch/apex/landing treatment and uncalibrated carry language.

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
