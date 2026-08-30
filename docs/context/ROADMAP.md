# Roadmap

## Now: secure the core round and reviewer foundation

- Run the remaining physical-device and footage-validation gates against the merged `main` release candidate.
- Verify persistence fallback and active-round restoration.
- Verify workout recovery and idempotent ending.
- Verify the Action Button setup and shot action on Apple Watch Ultra.
- Add automated tests for score calculations and round lifecycle.
- Validate the implemented timestamp-based tracker, evidence-anchored complete tracer, manual rescue and traced-video export against the documented 20 to 30 clip matrix.
- Extend the working iPhone/iPad reviewer with in-app Range recording and a persistent local session library.
- Preserve the long-session order proposal -> explicitly associated target golfer plus ball launch -> accepted clip -> evidence-backed tracer, manual rescue or no tracer.

## Next: release-quality Watch and Live Review experiences

- Complete accessibility, small-screen, Dynamic Type and outdoor-contrast review.
- Validate permission-denied and unavailable-service states.
- Confirm course detection and manual fallback on real locations.
- Establish repeatable archive, signing, TestFlight and release evidence.
- Exercise Live Review on a fixed tripod: bounded rolling capture, automatic post-roll replay, re-arm and interruption recovery.
- Measure on-device processing time, memory, battery, thermal and storage behaviour for 30 to 50-minute sessions.
- Build a consented, representative fixed-tripod validation set containing real shots, practice swings, impact-like range noise, neighbouring golfers and visible background balls. Measure accepted-shot precision and missed-shot rate separately from proposal recall.
- Validate and, only if necessary, fine-tune the integrated MIT WASB-SBDT Core ML tracker. The current acquire-and-track implementation passes three supplied positive originals, but that remains regression evidence rather than a representative accuracy result and contains no negative clips. The upstream public repository currently provides evaluation code while its training section is `TBA`, so a reproducible licensed training route remains an external prerequisite. Do not use Ultralytics AGPL weights or code in the distributed app without a separate licence.
- Measure and tune the existing single-ball association thresholds against labelled positives and negatives before considering a general ByteTrack integration. ByteTrack is not a detector and is unnecessary for the current one-ball lane. Keep SAM-style segmentation as an offline labelling aid rather than an iPhone runtime dependency.
- Build a held-out set containing daylight and night range footage, white and coloured balls, portrait and landscape framing, practice swings, club-head blur, range lights and neighbouring golfers. Measure track precision, missed-ball rate and false-tracer rate, with zero fabricated fallback paths.
- Keep the three supplied daylight/night and landscape/portrait positives as owner-controlled external regressions for impact timing, timestamp preservation, false acquisition and detector hand-off trimming. They are not by themselves sufficient training or release evidence.
- Complete fused hands-free detection and automatic post-roll replay only after the rolling capture foundation is reliable. The existing 60 fps target and stability/focus guidance are capture-readiness foundations, not a recorded rolling loop.

## Later: earned expansion

- Calibrated distance estimation only after tracer validation and known-ground-truth comparison.
- Optional iCloud synchronisation.
- Broader course data and caching after reliability and cost are proven.
- Handicap, GPS distance or social features only after the simple counter earns retention.

The reviewer does not promise numerical distance, cloud processing or unattended hands-free capture until those gates are passed. Local traced-video export is implemented; later items are hypotheses, not commitments.
