# Architecture

## Runtime shape

### iOS reviewer runtime

```text
RondeApp -> RondeRootView -> Apple account boundary
  -> RondeAppShell: Shot library, search/favourites and Settings
  -> RangeSessionEntryView: capture account ownership before Photos/Files work
  -> ReviewerStore: durable prepared import -> owned cancellable analysis
  -> ShotStudioView
       -> source AVPlayer and presentation-timestamp frame index
       -> ShotVideoEdit: reversible trim, output format and overlay choice
       -> ShotVideoTrace: observed-only automatic or labelled manual geometry
       -> FullScreenTracerEditor: draft-safe annotation
       -> ShotVideoExporter: fitted source + same trace, rebased MP4 and audio
  -> ReviewSessionArchive: typed read state, guarded atomic writes, relative media
  -> Supabase: existing private profile and lightweight metadata sync
```

`ShotVideoLayout` supplies the source-to-canvas geometry for preview and output. Full-source media is never overwritten. Export does not rerun detection. The active studio does not consume modelled carry, inferred landing or full-flight completion. Legacy perspective and Core Animation export components below remain experimental/compatibility code; ADR 0011 defines the current presentation.

The source retains dormant range-session association and live camera foundations. Neither is exposed in the single-shot studio.

## Boundaries

- `project.yml`: XcodeGen definition for targets, settings, entitlements and schemes.
- `Ronde iOS App/`: universal iPhone/iPad media library, reviewer, tracer and capture foundations.
- `Ronde iOS App/App/RondeAppShell.swift`: Apple-only entry, Shot library, Settings and studio routing with native navigation.
- `Ronde iOS App/Features/FullScreenTracerEditor.swift`: immersive manual trace placement over the fitted source video. It owns an unsaved local draft, direct Impact/Apex/Landing handles, frame stepping and Undo/Reset; only Save writes user-authored geometry through `ReviewerStore`.
- `Ronde iOS App/Persistence/ReviewSessionArchive.swift`: account-scoped JSON persistence for review metadata and saved geometry with atomic writes and complete file protection.
- `Ronde iOS App/Auth/`: secure Apple nonce generation, Supabase session restoration and profile/library metadata sync.
- `supabase/migrations/`: hosted `profiles` and `library_items` schema, ownership policies and anonymous-grant restrictions. Raw media has no hosted table or bucket.

## Reviewer boundaries

- The exposed reviewer MVP accepts one Photos/Files shot video up to 60 seconds, retains the full source range and opens directly into review. Long-session slicing and candidate acknowledgement are deliberately absent from this surface.
- A signed-in account activates only its own local archive. Signing out clears active in-memory sessions; another account receives a different archive filename and cannot inherit those sessions.
- Library, studio and Settings consume the local archive. Metadata sync is not on the critical path after account activation; cold offline authentication remains a separate gap.
- Individual review is video-first, with one concise trace state and grouped editing actions. Manual rescue leaves the nested review layout and presents full-screen; cancelling cannot mutate the stored automatic or manual geometry.
- Live Review has camera preview/state foundations, a 60 fps target, focus/exposure/white-balance settlement and locking where supported, Core Motion stability classification and framing guidance. A rolling segment writer, fused hands-free detection, automatic post-roll replay and temporary-buffer cleanup remain open.
- Proposals are not shots. Audio and body motion may nominate and deduplicate a moment, but only target-golfer evidence plus a stable golf-ball-specific launch can create an automatically accepted shot. Uncertain moments are recoverable; rejected background and different-golfer events never receive a clip or tracer.
- Shot-video imports bypass the candidate-management surface and open directly into full-source playback. They receive a tracer only when observed ball points pass the display gate; otherwise playback remains available with an explicit no-tracer state. `ShotVideoImportPolicy` rejects sources longer than 60 seconds for this MVP.
- `ReviewImportKind`, long-session analysis and target-golfer association remain dormant implementation foundations rather than exposed product choices.
- `ImpactCandidateAnalysisService` prefers clustered audio transients and runs preferred-orientation-aware `VNDetectHumanBodyPoseRequest` motion only when audio yields no usable candidate. This avoids a second full video decode on the common audio-backed One Shot path. A silent One Shot uses the body-motion source time as the ball tracker's acquisition anchor; if neither signal exists, it requires a manual marker rather than guessing from clip duration. The audio path selects the stereo AAC track when present, converts it to PCM and parses float, 16-bit and 32-bit sample formats. The pure selectors merge short bursts and apply a four-second refractory period.
- `LongSessionAnalysisService` separates `acceptedShots`, `uncertainMoments` and `rejectedEvents`. Its production defaults remain unavailable. The reviewer may install `FixedCameraSingleGolferAssociator` plus the tracker-backed launch detector only after the user confirms that the camera was fixed, the target golfer was selected and no other golfer was in frame. It otherwise fails closed.
- `TargetGolferAssociating` and `GolfBallLaunchDetecting` are independent injectable boundaries. Explicit different-golfer attribution is rejected; unresolved attribution remains uncertain. The fixed-camera adapter is a narrow session contract, not general person re-identification.
- `AcceptedShot.impactTime` is canonical and comes from validated target-golfer evidence. Clip planning, accepted-shot trajectory analysis and reviewer playback use that time rather than the coarser proposal timestamp.
- `ReviewClipService.exportAutomaticallyAcceptedClip` and the accepted-shot overload of `GolfBallTrajectoryAnalysisService` enforce the same decision boundary. Neither accepts an uncertain or rejected event. The legacy `TracedVideoExporter` renders experimental geometry into MOV. The active studio uses `ShotVideoExporter` for observed-only or manual MP4 output, normalising social derivatives to at most 60 fps while keeping source-time overlay evaluation.
- `GolfBallTrajectoryAnalysisService` runs `VNDetectTrajectoriesRequest` only in a bounded post-impact window, honours preferred orientation and passes each `CMSampleBuffer` so Vision receives its presentation timestamp. `targetFrameTime` is not media time. The request is a diagnostic moving-shape baseline, not a golf-ball classifier: generic motion remains inferred and is not displayable.
- `WASBGolfBallTrackingService` runs the packaged three-frame model over oriented source tiles. A phase-retaining near-30-Hz sampler and elapsed-source-time acquisition schedule feed a temporal selector. Committed identity survives finalisation; lost-track recovery and low-speed apex continuation require prediction-consistent evidence. Instrumentation records detector work and source cadence. Model weights remain unchanged and experimental.
- `GolfBallTrackSelector` is a purpose-built single-object association stage. Its windows and velocity thresholds use seconds and per-second units rather than nominal frame counts. It ranks competing post-impact paths, rejects weak or short motion, and trims an early club/body-to-ball detector hand-off before returning observed geometry. Analysis stops after sustained misses or an unproductive initial search. ByteTrack remains unnecessary unless the product later needs general multi-object association.
- `EvidenceAnchoredFlightPathExtrapolator` accepts only a valid, rising, source-timed observed track. Physical flight time begins at the independently detected impact, not at the first mid-air observation. When the tracker also supplies a unique observed launch anchor, the fit weights it independently and the connector starts at that exact source-frame position; it does not relabel connector interpolation as observed flight. The extrapolator grid-searches bounded launch distance, speed, elevation and horizon assumptions, solves vertical perspective scale and horizon from all observed samples, fits lateral perspective motion, retains the detector-attributed points and creates separate estimated geometry from launch to first observation and from the last observation through apex to landing. The last detector/model residual is weighted by `(1 - progress)²`, so it reaches zero rather than magnifying at long range. Final lateral displacement is capped by `min(0.055, max(0.012, abs(observedDX) * 2.5 + 0.008))`, retains an established observed direction and is blended with smoothstep inside an eight-thousandths-padded corridor. The final presentation point must remain below the fitted horizon, above launch and inside the safe frame. Normalised screen rate chooses only a broad chip-like, medium or full-shot launch prior; it is not converted into measured speed. Near-best selection scores produce a rounded 20th-to-80th-percentile carry range using a separate down-range damping assumption from the stronger screen-perspective convergence. The range is explicitly modelled and uncalibrated; precise carry and physical apex height are not supported.
- `TimedTrajectoryPath` validates strictly increasing source timestamps and produces the causal observed trail for the studio. `ShotVideoTrace` keeps only observed samples or a separately labelled manual annotation. Legacy `FullFlightRevealTimeline`, `PlayerSynchronizedTracer` and `TracedVideoExporter` retain the earlier model-completion experiment; their estimated geometry and carry gates are not the active presentation.
- `BallFlightEstimate.isDisplayable` requires observed ball evidence. Fixed fallbacks and generic Vision paths remain non-displayable. A manual path is stored separately as user-authored geometry and labelled `Manual trace`.
- The free runtime uses WASB-SBDT plus Core ML and local Swift association. YOLO and SAM are not app dependencies. SAM-style foundation models may assist offline labelling but are too large and unnecessary for this runtime.

## Data and privacy

Raw media, app-owned URLs, tracer geometry and analysis are local-only for MVP. Camera, microphone, photo-library import, add-only export and Sign in with Apple capability are declared through `project.yml`; denial or network failure must preserve access to an already activated local library wherever the requested feature does not require that capability.

The Supabase project stores only `profiles` and lightweight `library_items` metadata. Both tables have row-level security, authenticated ownership policies and no anonymous grants. The iOS app uses the public publishable key; no service-role credential belongs in the app or repository. Remote metadata is currently an account record and sync target, not a source for reconstructing missing local videos or geometry.

## September media and reliability changes

- Archive reads distinguish an absent library from corrupt or unreadable content. The archive writer refuses to replace unreadable data. Store save errors retain the dirty snapshot, expose retry and block sign-out until resolved. Deletion first commits the new archive, then removes media.
- App-owned source paths are encoded relative to the local media root and resolved for use in memory. Legacy absolute paths migrate only when ownership/path validation succeeds.
- Import ownership combines account ID and generation. It is captured before picker transfer and checked after asynchronous boundaries. The prepared-session callback runs after the initial durable save and routes the exact imported ID, independent of global selection. Active analysis tasks are cancelled on account changes; restored unfinished work becomes retryable.
- The decoder scheduler retains source-time phase near 30 Hz; full-frame acquisition uses a source-time schedule near 15 Hz. Normal links retain their short gap limit. A lost track can recover through a uniquely prediction-matched three-point tracklet, rather than appending a distant candidate. Final output revalidates the committed lineage after trimming.
- Apex reversal needs prior rise, low speed, bounded positive acceleration and a small prediction residual. These empirical gates and the unchanged model remain subject to held-out golf validation.
