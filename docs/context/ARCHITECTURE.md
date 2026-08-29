# Architecture

## Runtime shape

### Watch runtime

```text
RondeApp
  -> SwiftData ModelContainer
  -> ContentView
      -> setup flow
      -> active ShotCounterView
      -> RoundSummaryView and history
```

### iOS reviewer runtime

```text
ShotReviewerApp
  -> Photos/Files import and local media store
  -> AVFoundation metadata, exact clip export and playback
  -> event proposal stage
       -> impact-like audio and Vision body-motion signals
       -> nearby signals deduplicated without becoming shots
  -> real-shot evidence gate
       -> target-golfer swing and impact evidence
       -> golf-ball-specific launch evidence attributed to that golfer
       -> accepted, uncertain or rejected decision
  -> accepted shot only
       -> non-destructive impact -5s ... impact +5s clip plan
       -> policy-gated trajectory analysis and tracer
  -> uncertain correction queue without a tracer
  -> rejected background/different-golfer events omitted from the workflow
  -> AVPlayer video-first review canvas
       -> MIT WASB-SBDT Core ML heatmaps over source-resolution tiles
       -> single-ball temporal association and track-quality gate
       -> source-time tracer reveal, or explicit no-tracer state
  -> exact local clip export service (not yet connected to reviewer UI/share)
```

The current source also contains a live camera preview/state foundation. In-app Range recording, rolling segment writing, fused hands-free detection and automatic post-roll replay are not implemented yet.

### Watch round lifecycle

```text
Round lifecycle
  -> SwiftData Round + HoleScore
  -> optional HealthKit golf workout
  -> optional pedometer and location context
  -> App Intents shot action
```

## Boundaries

- `Ronde Watch App/RondeApp.swift`: application entry, persistence container and debug preview routing.
- `ContentView.swift`: selects home, active round or summary from persisted state.
- `Models/`: SwiftData round and hole state plus course data structures.
- `Views/SetupFlow/`: course, hole, par and ready flow.
- `Views/InRound/`: scoring and hole-transition surfaces.
- `Views/Summary/`: completed-round review.
- `Services/WorkoutManager.swift`: HealthKit workout lifecycle and recovery.
- `Services/LocationService.swift`: permission and nearby-course location.
- `Services/PedometerService.swift`: walking metrics.
- `Services/CourseLibrary.swift` and `Resources/SydneyCourses.json`: bundled course data.
- `Intents/ShotCountIntent.swift`: Action Button-compatible App Intents.
- `project.yml`: XcodeGen definition for targets, settings, entitlements and schemes.
- `Ronde iOS App/`: universal iPhone/iPad reviewer source and packaging companion. The Watch does not call into this runtime to count shots.

## Reviewer boundaries

- Range Session currently supports local Photos/Files import, metadata inspection, a fail-closed real-shot decision pipeline, manual correction and logical five-second pre/post clip playback. An exact accepted-shot-only local export service exists, but generated-clip library integration, in-app Range recording and persistent session-library management remain open.
- Live Review currently has camera preview/state foundations only. A rolling segment writer, fused hands-free detection, automatic post-roll replay and temporary-buffer cleanup remain open.
- Proposals are not shots. Audio and body motion may nominate and deduplicate a moment, but only target-golfer evidence plus a stable golf-ball-specific launch can create an automatically accepted shot. Uncertain moments are recoverable; rejected background and different-golfer events never receive a clip or tracer.
- Short single-shot imports bypass the candidate-management surface and open directly into playback. They receive a tracer only when observed ball points pass the same display gate; otherwise playback remains available with an explicit no-tracer state. Candidate queues, shot/practice decisions and manual segmentation remain available only for multi-shot recordings.
- `ReviewImportKind` carries the explicit One Shot or Range Session choice through import, analysis and review. The app does not infer the workflow from an arbitrary duration threshold.
- `ImpactCandidateAnalysisService` prefers clustered audio transients and falls back to preferred-orientation-aware `VNDetectHumanBodyPoseRequest` motion. The audio path selects the stereo AAC track when present, converts it to PCM and parses float, 16-bit and 32-bit sample formats. The pure selectors merge short bursts and apply a four-second refractory period.
- `LongSessionAnalysisService` separates `acceptedShots`, `uncertainMoments` and `rejectedEvents`. Its target-golfer and launch-evidence adapters still report model unavailable, so long-session imports fail closed rather than automatically accepting generic motion. The packaged tracker does not by itself establish which golfer struck the ball.
- `TargetGolferAssociating` and `GolfBallLaunchDetecting` are independent injectable boundaries. Both default to model-unavailable evidence. Explicit different-golfer attribution is rejected; unresolved attribution remains uncertain.
- `AcceptedShot.impactTime` is canonical and comes from validated target-golfer evidence. Clip planning, accepted-shot trajectory analysis and reviewer playback use that time rather than the coarser proposal timestamp.
- `ReviewClipService.exportAutomaticallyAcceptedClip` and the accepted-shot overload of `GolfBallTrajectoryAnalysisService` enforce the same decision boundary. Neither accepts an uncertain or rejected event. Rendered derivative export is not connected to the UI, so Share is deliberately absent rather than sending the full source as though it were a finished shot clip.
- `GolfBallTrajectoryAnalysisService` runs `VNDetectTrajectoriesRequest` only in a bounded post-impact window, honours preferred orientation and passes each `CMSampleBuffer` so Vision receives its presentation timestamp. `targetFrameTime` is not media time. The request is a diagnostic moving-shape baseline, not a golf-ball classifier: generic motion remains inferred and is not displayable.
- `WASBGolfBallTrackingService` loads the packaged 2.6 MB MIT-licensed NTT WASB-SBDT Core ML model. It stacks three oriented RGB frames, evaluates overlapping 512 by 288 source-resolution tiles over the upper flight search area, suppresses duplicate peaks and passes candidates to `GolfBallTrackSelector`.
- `GolfBallTrackSelector` is a purpose-built single-object association stage. It requires at least seven post-impact detections, one- or two-frame gaps, minimum motion, stable direction, prediction consistency, source-time proximity to impact, coverage and upward displacement. ByteTrack remains unnecessary unless the product later needs general multi-object association.
- `TracerRevealTimeline` and `PlayerSynchronizedTracer` use `AVPlayer` item time rather than nominal frame count. Model-backed paths start at the first observed source timestamp, reveal the actual detected polyline and hold afterwards. Reduced Motion shows the complete observed segment at its first timestamp.
- `BallFlightEstimate.isDisplayable` requires at least three observed points, an observed trajectory and an observed or observed-plus-inferred source. Fixed fallbacks, generic Vision paths and model tracks that fail the stricter seven-point selector remain non-displayable.
- The free runtime uses WASB-SBDT plus Core ML and local Swift association. YOLO and SAM are not app dependencies. SAM-style foundation models may assist offline labelling but are too large and unnecessary for this runtime.

## Data and privacy

Round history is local SwiftData. HealthKit, location and motion access are optional capability inputs. Do not add analytics, remote round storage or background location without an explicit product, privacy and operational decision.

Reviewer media and analysis are local-only for MVP. Camera, microphone, photo-library import and add-only export permissions are declared in `project.yml`; denial must leave the Watch counter usable and the reviewer must explain the unavailable capability.
