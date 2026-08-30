# Roadmap

## Now: secure the core round and reviewer foundation

- Run the remaining physical-device and footage-validation gates against the merged `main` release candidate.
- Verify persistence fallback and active-round restoration.
- Verify workout recovery and idempotent ending.
- Verify the Action Button setup and shot action on Apple Watch Ultra.
- Add automated tests for score calculations and round lifecycle.
- Finish the Apple account gate: verify the already-enabled Supabase provider for `com.ronde` against the Apple Developer capability, then test first sign-in, repeat sign-in, session restoration and sign-out on a signed iPhone.
- Validate account-scoped local archive restoration, metadata sync failure recovery, deletion reconciliation and row-level-security isolation with two controlled test accounts.
- Validate the implemented timestamp-based tracker, perspective-aware complete tracer, rough carry range, manual rescue and traced-video export against the documented 20 to 30 short-shot-video matrix.
- Import and label the exact five videos from the latest TestFlight check. Reproduce the four misses and the inaccurate positive with per-stage instrumentation before changing impact, detector, association or extrapolation thresholds.
- Inspect every exported positive frame by frame for a causal trail that remains behind the visible ball, observed-versus-estimated styling, visible apex, bounded landing, orientation and source cadence. Run the same export matrix on a signed physical iPhone because the current iOS 26.5 Simulator compositor crashes in its IOSurface path.
- Keep Range Session slicing and Live Review dormant until the one-video/one-shot MVP earns representative footage accuracy and physical-iPhone performance evidence.

## Next: release-quality Watch and Live Review experiences

- Complete accessibility, small-screen, Dynamic Type and outdoor-contrast review.
- Validate permission-denied and unavailable-service states.
- Confirm course detection and manual fallback on real locations.
- Establish repeatable archive, signing, TestFlight and release evidence.
- Measure on-device processing time, memory, battery, thermal and storage behaviour across representative shot videos up to 60 seconds.
- Build a consented, representative fixed-tripod validation set containing real shots, practice swings, impact-like range noise, neighbouring golfers and visible background balls. Measure accepted-shot precision and missed-shot rate separately from proposal recall.
- Establish a golf-specific detector baseline and fine-tuning path. The MIT WASB-SBDT Core ML tracker passes three supplied positive regressions but achieved only one inaccurate automatic trace across the latest five-video TestFlight check. The upstream public repository currently provides evaluation code while its training section is `TBA`, so a reproducible licensed training route and consented golf labels are external prerequisites. Use Apple Core ML for on-device execution and evaluate Create ML or a permissively licensed training stack; do not distribute Ultralytics AGPL weights or code without a separate licence.
- Measure and tune the existing single-ball association thresholds against labelled positives and negatives before considering a general ByteTrack integration. ByteTrack is not a detector and is unnecessary for the current one-ball lane. Keep SAM-style segmentation as an offline labelling aid rather than an iPhone runtime dependency.
- Build a held-out set containing daylight and night range footage, white and coloured balls, portrait and landscape framing, practice swings, club-head blur, range lights and neighbouring golfers. Measure track precision, missed-ball rate and false-tracer rate, with zero fabricated fallback paths.
- Keep the three supplied daylight/night and landscape/portrait positives as owner-controlled external regressions for impact timing, timestamp preservation, false acquisition and detector hand-off trimming. They are not by themselves sufficient training or release evidence.
- Reconsider long-session slicing and hands-free automatic replay only after the short-shot MVP is reliable. The existing 60 fps target and stability/focus guidance are dormant capture-readiness foundations, not a recorded rolling loop.

## Later: earned expansion

- Calibrated precise carry and physical apex height only after tracer validation and known-ground-truth comparison. Validate the MVP's broad model-carry prior separately for driver, iron and wedge footage; it remains explicitly uncalibrated until then.
- Optional metadata restoration and cross-device reconciliation after ownership and missing-local-media states are designed.
- Optional encrypted raw-media backup only through a new explicit privacy, retention, cost and deletion decision.
- Broader course data and caching after reliability and cost are proven.
- Handicap, GPS distance or social features only after the simple counter earns retention.

The reviewer does not promise measured distance, cloud media processing, cross-device video recovery or unattended hands-free capture until those gates are passed. A broad rough carry range, local traced-video export and private lightweight metadata sync are implemented; later items are hypotheses, not commitments.
