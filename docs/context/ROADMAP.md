# Roadmap

## Now: secure the core round and reviewer foundation

- Publish the reliability and visual release candidate to `main`.
- Verify persistence fallback and active-round restoration.
- Verify workout recovery and idempotent ending.
- Verify the Action Button setup and shot action on Apple Watch Ultra.
- Add automated tests for score calculations and round lifecycle.
- Extend the working iPhone/iPad reviewer slice with in-app Range recording and a persistent local session library.
- Keep validating direct source-time single-shot review and the imported long-session evidence gate across uploaded frame rates. A long-session result must preserve the order proposal -> target golfer plus ball launch -> accepted clip -> evidence-backed tracer or no tracer.

## Next: release-quality Watch and Live Review experiences

- Complete accessibility, small-screen, Dynamic Type and outdoor-contrast review.
- Validate permission-denied and unavailable-service states.
- Confirm course detection and manual fallback on real locations.
- Establish repeatable archive, signing, TestFlight and release evidence.
- Exercise Live Review on a fixed tripod: bounded rolling capture, automatic post-roll replay, re-arm and interruption recovery.
- Measure on-device processing time, memory, battery, thermal and storage behaviour for 30 to 50-minute sessions.
- Build a consented, representative fixed-tripod validation set containing real shots, practice swings, impact-like range noise, neighbouring golfers and visible background balls. Measure accepted-shot precision and missed-shot rate separately from proposal recall.
- Validate and, only if necessary, fine-tune the integrated MIT WASB-SBDT Core ML tracker. The current source-resolution tiled model plus single-ball linker passed one supplied night-range clip, but that is feasibility evidence rather than a representative accuracy result. Do not use Ultralytics AGPL weights or code in the distributed app without a separate licence.
- Measure and tune the existing single-ball association thresholds against labelled positives and negatives before considering a general ByteTrack integration. ByteTrack is not a detector and is unnecessary for the current one-ball lane. Keep SAM-style segmentation as an offline labelling aid rather than an iPhone runtime dependency.
- Build a held-out set containing daylight and night range footage, white and coloured balls, portrait and landscape framing, practice swings, club-head blur, range lights and neighbouring golfers. Measure track precision, missed-ball rate and false-tracer rate, with zero fabricated fallback paths.
- Use the supplied 30 fps night-range clip as a regression case for impact timing, timestamp preservation, small-object crops and false-tracer rejection. It is not by itself sufficient training or release evidence.
- Add fused hands-free detection and automatic post-roll replay only after the rolling capture foundation is reliable.

## Later: earned expansion

- Calibrated distance estimation only after tracer validation and known-ground-truth comparison.
- Optional iCloud synchronisation.
- Broader course data and caching after reliability and cost are proven.
- Handicap, GPS distance or social features only after the simple counter earns retention.

The reviewer does not promise numerical distance, cloud processing or export automation until those gates are passed. Later items are hypotheses, not commitments.
