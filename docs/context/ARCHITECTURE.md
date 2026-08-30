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
       -> timestamp-based full-frame acquisition and local-ROI tracking
       -> single-ball temporal association and track-quality gate
       -> solid observed launch plus dashed evidence-anchored estimate
       -> labelled manual rescue or explicit no-tracer state
  -> traced-video renderer and native share sheet using the reviewed geometry
```

The current source also contains a 60 fps live camera preview/state foundation with focus, exposure, white-balance locking and Core Motion stability guidance. In-app Range recording, rolling segment writing, fused hands-free detection and automatic post-roll replay are not implemented yet.

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

- Range Session supports local Photos/Files import, metadata inspection, a fail-closed real-shot decision pipeline, explicit fixed-camera single-golfer opt-in, manual correction and logical five-second pre/post clip playback. Exact accepted-shot clip export and traced-video rendering exist, but generated-clip library integration, in-app Range recording and persistent session-library management remain open.
- Live Review has camera preview/state foundations, a 60 fps target, focus/exposure/white-balance settlement and locking where supported, Core Motion stability classification and framing guidance. A rolling segment writer, fused hands-free detection, automatic post-roll replay and temporary-buffer cleanup remain open.
- Proposals are not shots. Audio and body motion may nominate and deduplicate a moment, but only target-golfer evidence plus a stable golf-ball-specific launch can create an automatically accepted shot. Uncertain moments are recoverable; rejected background and different-golfer events never receive a clip or tracer.
- Short single-shot imports bypass the candidate-management surface and open directly into playback. They receive a tracer only when observed ball points pass the same display gate; otherwise playback remains available with an explicit no-tracer state. Candidate queues, shot/practice decisions and manual segmentation remain available only for multi-shot recordings.
- `ReviewImportKind` carries the explicit One Shot or Range Session choice through import, analysis and review. The app does not infer the workflow from an arbitrary duration threshold.
- `ImpactCandidateAnalysisService` prefers clustered audio transients and runs preferred-orientation-aware `VNDetectHumanBodyPoseRequest` motion only when audio yields no usable candidate. This avoids a second full video decode on the common audio-backed One Shot path. A silent One Shot uses the body-motion source time as the ball tracker's acquisition anchor; if neither signal exists, it requires a manual marker rather than guessing from clip duration. The audio path selects the stereo AAC track when present, converts it to PCM and parses float, 16-bit and 32-bit sample formats. The pure selectors merge short bursts and apply a four-second refractory period.
- `LongSessionAnalysisService` separates `acceptedShots`, `uncertainMoments` and `rejectedEvents`. Its production defaults remain unavailable. The reviewer may install `FixedCameraSingleGolferAssociator` plus the tracker-backed launch detector only after the user confirms that the camera was fixed, the target golfer was selected and no other golfer was in frame. It otherwise fails closed.
- `TargetGolferAssociating` and `GolfBallLaunchDetecting` are independent injectable boundaries. Explicit different-golfer attribution is rejected; unresolved attribution remains uncertain. The fixed-camera adapter is a narrow session contract, not general person re-identification.
- `AcceptedShot.impactTime` is canonical and comes from validated target-golfer evidence. Clip planning, accepted-shot trajectory analysis and reviewer playback use that time rather than the coarser proposal timestamp.
- `ReviewClipService.exportAutomaticallyAcceptedClip` and the accepted-shot overload of `GolfBallTrajectoryAnalysisService` enforce the same decision boundary. Neither accepts an uncertain or rejected event. `TracedVideoExporter` renders the currently reviewed tracer geometry into a local MOV, preserves common source cadences up to 240 fps, and exposes it through the native share sheet without re-running detection.
- `GolfBallTrajectoryAnalysisService` runs `VNDetectTrajectoriesRequest` only in a bounded post-impact window, honours preferred orientation and passes each `CMSampleBuffer` so Vision receives its presentation timestamp. `targetFrameTime` is not media time. The request is a diagnostic moving-shape baseline, not a golf-ball classifier: generic motion remains inferred and is not displayable.
- `WASBGolfBallTrackingService` loads the packaged 2.6 MB MIT-licensed NTT WASB-SBDT Core ML model. It reads sequential `CMSampleBuffer`s, preserves presentation timestamps and samples them at about 30 Hz regardless of source FPS. During the first 0.65 seconds after impact it evaluates alternate full-frame windows so the first high-confidence moving speck cannot immediately exclude the ball. Eight linked observations are required before the search narrows to a predicted local ROI or any subsequently trimmed path may become displayable; periodic full-frame reacquisition remains available. Each analysed three-frame window allocates one reusable 5.3 MB model input tensor, refills it for every source-resolution tile and drains Core ML prediction temporaries before the next tile. Progress is coalesced to roughly four updates per model window while cancellation remains per tile. The identity-orientation path reuses BGRA buffers and vectorised conversion; transformed media retains the orientation render. Instrumentation reports decoded, skipped and sampled frames, model input allocations, search modes, model windows, tiles, candidates and selected points.
- `GolfBallTrackSelector` is a purpose-built single-object association stage. Its windows and velocity thresholds use seconds and per-second units rather than nominal frame counts. It ranks competing post-impact paths, rejects weak or short motion, and trims an early club/body-to-ball detector hand-off before returning observed geometry. Analysis stops after sustained misses or an unproductive initial search. ByteTrack remains unnecessary unless the product later needs general multi-object association.
- `EvidenceAnchoredFlightPathExtrapolator` accepts only a valid, rising, source-timed observed launch. It retains observed points and creates a separate bounded screen-space continuation through a later apex to landing. The continuation is an estimate and cannot produce numerical distance or height.
- `TracerRevealTimeline` and `PlayerSynchronizedTracer` use `AVPlayer` item time rather than nominal frame count. Model-backed paths reveal the observed segment as a solid line and the inferred continuation as a dashed line. Reduced Motion removes progressive animation while preserving provenance.
- `BallFlightEstimate.isDisplayable` requires observed ball evidence. Fixed fallbacks and generic Vision paths remain non-displayable. A manual path is stored separately as user-authored geometry and labelled `Manual trace`.
- The free runtime uses WASB-SBDT plus Core ML and local Swift association. YOLO and SAM are not app dependencies. SAM-style foundation models may assist offline labelling but are too large and unnecessary for this runtime.

## Data and privacy

Round history is local SwiftData. HealthKit, location and motion access are optional capability inputs. Do not add analytics, remote round storage or background location without an explicit product, privacy and operational decision.

Reviewer media and analysis are local-only for MVP. Camera, microphone, photo-library import and add-only export permissions are declared in `project.yml`; denial must leave the Watch counter usable and the reviewer must explain the unavailable capability.
