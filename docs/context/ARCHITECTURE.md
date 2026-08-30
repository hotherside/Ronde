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
RondeCompanionApp
  -> RondeRootView
       -> native Sign in with Apple
       -> Supabase Auth session and private profile
  -> RondeAppShell
       -> Home: recent reviews and evidence-backed activity metrics
       -> Library: search, trace and favourite filters
       -> Profile: account, activity and metadata-sync state
  -> account-scoped ReviewSessionArchive
  -> one Photos/Files shot-video import, maximum 60 seconds
  -> AVFoundation metadata, full-source playback and local media store
  -> internal impact-time analysis
       -> impact-like audio
       -> preferred-orientation body motion only when audio is unavailable
  -> golf-ball-specific launch evidence gate
  -> AVPlayer video-first review canvas
       -> MIT WASB-SBDT Core ML heatmaps over source-resolution tiles
       -> timestamp-based full-frame acquisition and local-ROI tracking
       -> single-ball temporal association and track-quality gate
       -> source-frame launch anchor plus perspective-aware launch-to-landing fit
       -> one tapered solid-purple ribbon; estimated ranges use subtly lower opacity
       -> visible image-space apex and rough uncalibrated carry range when supported
       -> labelled manual rescue or explicit no-tracer state
       -> full-screen manual editor with local draft, frame stepping and explicit Cancel/Save
  -> traced-video renderer and native share sheet using the reviewed geometry
  -> Supabase library_items metadata upsert under per-user row-level security
```

The current source also contains dormant long-session proposal/association code and a 60 fps live camera preview/state foundation with focus, exposure, white-balance locking and Core Motion stability guidance. These are not exposed in the current MVP. In-app Range recording, rolling segment writing, fused hands-free detection and automatic post-roll replay are not implemented.

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
- `Ronde iOS App/App/RondeAppShell.swift`: Apple-only entry, Home, Library, Profile and media-detail routing. The native tab bar supplies Liquid Glass on iOS 26; older supported systems use SwiftUI's system material behaviour.
- `Ronde iOS App/Features/FullScreenTracerEditor.swift`: immersive manual trace placement over the fitted source video. It owns an unsaved local draft, direct Impact/Apex/Landing handles, frame stepping and Undo/Reset; only Save writes user-authored geometry through `ReviewerStore`.
- `Ronde iOS App/Persistence/ReviewSessionArchive.swift`: account-scoped JSON persistence for review metadata and saved geometry with atomic writes and complete file protection.
- `Ronde iOS App/Auth/`: secure Apple nonce generation, Supabase session restoration and profile/library metadata sync.
- `supabase/migrations/`: hosted `profiles` and `library_items` schema, ownership policies and anonymous-grant restrictions. Raw media has no hosted table or bucket.

## Reviewer boundaries

- The exposed reviewer MVP accepts one Photos/Files shot video up to 60 seconds, retains the full source range and opens directly into review. Long-session slicing and candidate acknowledgement are deliberately absent from this surface.
- A signed-in account activates only its own local archive. Signing out clears active in-memory sessions; another account receives a different archive filename and cannot inherit those sessions.
- Home, Library and Profile consume the local session archive. The cloud is not on the critical path for review, editing, metrics or playback.
- Individual review is video-first and suppresses duplicate in-video evidence cards because provenance and metrics sit in the review panel below. Manual rescue leaves the nested review layout and presents full-screen; cancelling cannot mutate the stored automatic or manual geometry.
- Live Review has camera preview/state foundations, a 60 fps target, focus/exposure/white-balance settlement and locking where supported, Core Motion stability classification and framing guidance. A rolling segment writer, fused hands-free detection, automatic post-roll replay and temporary-buffer cleanup remain open.
- Proposals are not shots. Audio and body motion may nominate and deduplicate a moment, but only target-golfer evidence plus a stable golf-ball-specific launch can create an automatically accepted shot. Uncertain moments are recoverable; rejected background and different-golfer events never receive a clip or tracer.
- Shot-video imports bypass the candidate-management surface and open directly into full-source playback. They receive a tracer only when observed ball points pass the display gate; otherwise playback remains available with an explicit no-tracer state. `ShotVideoImportPolicy` rejects sources longer than 60 seconds for this MVP.
- `ReviewImportKind`, long-session analysis and target-golfer association remain dormant implementation foundations rather than exposed product choices.
- `ImpactCandidateAnalysisService` prefers clustered audio transients and runs preferred-orientation-aware `VNDetectHumanBodyPoseRequest` motion only when audio yields no usable candidate. This avoids a second full video decode on the common audio-backed One Shot path. A silent One Shot uses the body-motion source time as the ball tracker's acquisition anchor; if neither signal exists, it requires a manual marker rather than guessing from clip duration. The audio path selects the stereo AAC track when present, converts it to PCM and parses float, 16-bit and 32-bit sample formats. The pure selectors merge short bursts and apply a four-second refractory period.
- `LongSessionAnalysisService` separates `acceptedShots`, `uncertainMoments` and `rejectedEvents`. Its production defaults remain unavailable. The reviewer may install `FixedCameraSingleGolferAssociator` plus the tracker-backed launch detector only after the user confirms that the camera was fixed, the target golfer was selected and no other golfer was in frame. It otherwise fails closed.
- `TargetGolferAssociating` and `GolfBallLaunchDetecting` are independent injectable boundaries. Explicit different-golfer attribution is rejected; unresolved attribution remains uncertain. The fixed-camera adapter is a narrow session contract, not general person re-identification.
- `AcceptedShot.impactTime` is canonical and comes from validated target-golfer evidence. Clip planning, accepted-shot trajectory analysis and reviewer playback use that time rather than the coarser proposal timestamp.
- `ReviewClipService.exportAutomaticallyAcceptedClip` and the accepted-shot overload of `GolfBallTrajectoryAnalysisService` enforce the same decision boundary. Neither accepts an uncertain or rejected event. `TracedVideoExporter` renders the currently reviewed tracer geometry into a local MOV, preserves common source cadences up to 240 fps, and exposes it through the native share sheet without re-running detection.
- `GolfBallTrajectoryAnalysisService` runs `VNDetectTrajectoriesRequest` only in a bounded post-impact window, honours preferred orientation and passes each `CMSampleBuffer` so Vision receives its presentation timestamp. `targetFrameTime` is not media time. The request is a diagnostic moving-shape baseline, not a golf-ball classifier: generic motion remains inferred and is not displayable.
- `WASBGolfBallTrackingService` loads the packaged 2.6 MB MIT-licensed NTT WASB-SBDT Core ML model. It reads sequential `CMSampleBuffer`s, preserves presentation timestamps and samples them at about 30 Hz regardless of source FPS. A bounded 2 ms early-arrival tolerance retains real near-30 fps source frames, including the measured 30.087 fps regression, while higher-rate sources remain sub-sampled near 30 Hz. During the first 0.65 seconds after impact it evaluates alternate full-frame windows so the first high-confidence moving speck cannot immediately exclude the ball. Eight linked observations are required before the search narrows to a predicted local ROI or any subsequently trimmed path may become displayable; periodic full-frame reacquisition remains available. An every-window acquisition experiment is explicitly not part of this design: it selected a wrong object on the labelled Landscape A regression because the current competition favoured a denser false path. Independently, a bounded source-frame luminance check around impact looks for one compact bright object inside the accepted trajectory corridor that is present before impact and disappears after it. This optional launch anchor is accepted only when its score is uniquely stronger than competing objects; ambiguity or missing evidence yields no anchor. Each analysed three-frame window allocates one reusable 5.3 MB model input tensor, refills it for every source-resolution tile and drains Core ML prediction temporaries before the next tile. Progress is coalesced to roughly four updates per model window while cancellation remains per tile. The identity-orientation path reuses BGRA buffers and vectorised conversion; transformed media retains the orientation render. Instrumentation reports decoded, skipped and sampled frames, model input allocations, search modes, model windows, tiles, candidates and selected points. Simulator builds use CPU-only model execution to avoid a current MPSGraph runtime failure; physical iPhone builds retain automatic compute-unit selection.
- `GolfBallTrackSelector` is a purpose-built single-object association stage. Its windows and velocity thresholds use seconds and per-second units rather than nominal frame counts. It ranks competing post-impact paths, rejects weak or short motion, and trims an early club/body-to-ball detector hand-off before returning observed geometry. Analysis stops after sustained misses or an unproductive initial search. ByteTrack remains unnecessary unless the product later needs general multi-object association.
- `EvidenceAnchoredFlightPathExtrapolator` accepts only a valid, rising, source-timed observed track. Physical flight time begins at the independently detected impact, not at the first mid-air observation. When the tracker also supplies a unique observed launch anchor, the fit weights it independently and the connector starts at that exact source-frame position; it does not relabel connector interpolation as observed flight. The extrapolator grid-searches bounded launch distance, speed, elevation and horizon assumptions, solves vertical perspective scale and horizon from all observed samples, fits lateral perspective motion, retains the detector-attributed points and creates separate estimated geometry from launch to first observation and from the last observation through apex to landing. The last detector/model residual is weighted by `(1 - progress)²`, so it reaches zero rather than magnifying at long range. Final lateral displacement is capped by `min(0.055, max(0.012, abs(observedDX) * 2.5 + 0.008))`, retains an established observed direction and is blended with smoothstep inside an eight-thousandths-padded corridor. The final presentation point must remain below the fitted horizon, above launch and inside the safe frame. Normalised screen rate chooses only a broad chip-like, medium or full-shot launch prior; it is not converted into measured speed. Near-best selection scores produce a rounded 20th-to-80th-percentile carry range using a separate down-range damping assumption from the stronger screen-perspective convergence. The range is explicitly modelled and uncalibrated; precise carry and physical apex height are not supported.
- `TimedTrajectoryPath` validates one strictly increasing presentation timestamp per detector point and supplies the sample-derived lag, capped at 50 ms, that keeps the observed trail behind the source ball. `FullFlightRevealTimeline` assigns monotonic model times to the impact connector and landing continuation, preserves detector timestamps exactly, smooths the combined point sequence once and exposes cumulative-distance provenance ranges. It accepts the original model duration separately from an optional shorter presentation duration. Model timestamps remain unchanged through the minimum-image-`y` continuation apex; only post-apex descent samples may be linearly remapped into the remaining source time. The completed-path hold is at most 120 ms, and a source too short for apex plus lag produces only a causal prefix with no landing/carry gate. `PlayerSynchronizedTracer` and `TracedVideoExporter` consume the same linear time-to-distance keyframes and render one smoothly tapered solid-purple ribbon. Estimated ranges use subtly lower opacity; they do not introduce dashes, seams or a second drawing order. `EST. APEX` and `EST. LANDING` appear only when their path distances are reached, and model carry appears at landing. Reduced Motion reveals the available styled path at impact while preserving provenance and the landing gate.
- `BallFlightEstimate.isDisplayable` requires observed ball evidence. Fixed fallbacks and generic Vision paths remain non-displayable. A manual path is stored separately as user-authored geometry and labelled `Manual trace`.
- The free runtime uses WASB-SBDT plus Core ML and local Swift association. YOLO and SAM are not app dependencies. SAM-style foundation models may assist offline labelling but are too large and unnecessary for this runtime.

## Data and privacy

Round history is local SwiftData. HealthKit, location and motion access are optional capability inputs. Do not add analytics, remote round storage or background location without an explicit product, privacy and operational decision.

Reviewer raw media, app-owned URLs, tracer geometry and analysis are local-only for MVP. Camera, microphone, photo-library import, add-only export and Sign in with Apple capability are declared through `project.yml`; denial or network failure must leave the Watch counter usable and preserve an already activated local reviewer library.

The Supabase project stores only `profiles` and lightweight `library_items` metadata. Both tables have row-level security, authenticated ownership policies and no anonymous grants. The iOS app uses the public publishable key; no service-role credential belongs in the app or repository. Remote metadata is currently an account record and sync target, not a source for reconstructing missing local videos or geometry.
