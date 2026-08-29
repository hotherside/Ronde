# Ronde product contract

**Status:** current working contract

**Reviewed:** 24 August 2026

## Product

Ronde is an Apple Watch golf shot counter and a local-only iPhone/iPad shot reviewer. The Watch remains the independent core product for keeping an honest score without repeatedly handling a phone. The reviewer helps golfers inspect range swings, create useful clips and review a ball path only when the uploaded frames support a defensible track.

The essential loop is:

1. Start a quick 9, quick 18 or known course round.
2. Confirm hole count and par.
3. Start a golf workout when permission allows.
4. Log one shot with the on-screen control or configured Action Button action.
5. Undo mistakes and move between holes without losing state.
6. Finish and review shots, par delta, walking distance and duration.
7. Keep the completed round locally.

## Experience rules

- The current hole, shots and score must be legible at a glance outdoors.
- Core counting works offline and without HealthKit, location or motion permission.
- Permission denial is a degraded capability, not a blocked round.
- An incomplete active round returns after relaunch when persistence is available.
- Destructive actions such as discarding a round require deliberate confirmation.
- Haptics support actions but never replace visible state.
- Ronde does not claim automatic swing detection, GPS yardage, handicap calculation or social competition unless those behaviours are implemented and verified.
- The Watch app remains independently usable and does not depend on the reviewer, network access or a paired phone at runtime.
- The iPhone/iPad reviewer uses a light appearance and supports fixed-tripod, down-the-line range footage.
- A short single-swing import opens directly into an automatically playing, video-first Shot Review. When a ball-specific track passes the evidence gate, its tracer is hidden before impact, reveals progressively in source time and remains visible after the tracked flight completes. Otherwise the review explicitly says that ball flight was not tracked. Candidate management and segmentation are reserved for recordings with multiple detected shots.
- The selected `One Shot` or `Range Session` intent is authoritative. Duration and frame rate affect processing cost and evidence quality but do not decide which review workflow the user receives.
- A longer Range Session first creates non-authoritative event proposals. An automatic real shot requires both a swing/impact attributed to the target golfer and a stable golf-ball launch attributed to that golfer within the allowed source-time window.
- Only accepted real shots enter the primary shot rail, receive a non-destructive clip plan and become tracer eligible. Uncertain moments remain in a collapsed correction queue without tracers; rejected background events, generic motion and different-golfer events are hidden from the primary workflow.
- An accepted shot clip defaults to impact minus five seconds through impact plus five seconds. Validated target-golfer impact time is canonical once available; a coarser proposal timestamp must not drive clipping, playback or tracer reveal. The source range is clamped at recording boundaries, trimming is non-destructive, and the original media is retained until the user explicitly removes it.
- Live Review may use a temporary rolling capture buffer for hands-free one-shot feedback. It retains the candidate clip only after an impact-like event, plays it automatically after post-roll and processing, and discards unrelated buffer segments.
- The MVP must never fabricate a tracer. A short review without enough ball-specific points remains playable and says `Ball flight not tracked`; it does not receive default launch, apex or landing geometry.
- Uploaded files are processed using their own presentation timestamps and orientation. No specific recording frame rate is required; lower temporal or spatial quality may reduce tracking confidence and result in no tracer.
- Native Vision trajectory analysis may be used as a constrained diagnostic baseline, but generic moving-shape points cannot accept a real shot, enable a tracer or earn an `Observed` golf-ball label. A one-shot review may show an observed segment only when the packaged sports-ball model produces a temporally consistent post-impact track. Long-session shot acceptance additionally requires target-golfer association.
- An automatic tracer may show only the confidence-gated two-dimensional model observations and must use their source presentation times. Generic parabolic Vision observations, fixed fallbacks and geometric projections must not create a visible tracer. Held-out positive and negative footage, false-tracer measurement and physical-device performance remain release gates rather than prerequisites for keeping the current evidence-gated prototype available.
- Numerical distance is a later experiment requiring a saved calibration setup and validation against known ground truth. It is not an MVP promise.
- Reviewer media and analysis stay on-device for MVP. No cloud upload, remote round storage, analytics, or background location is part of this scope.

## Platform boundary

- The watchOS application is the independent core shot-counter product.
- The iOS target is a universal iPhone/iPad Shot Reviewer and also remains the packaging companion required by the watch bundle relationship.
- Reviewer media processing uses Apple on-device frameworks where available, with confidence and unsupported-input states exposed honestly. Physical-device performance and model quality remain validation gates.
- SwiftData owns local round history.
- HealthKit owns the optional golf workout session.
- Core Location and the bundled Sydney course library support nearby-course selection.
- App Intents supplies the Action Button-compatible shot action, but real hardware configuration and invocation require manual verification.
- AVFoundation, Vision human-body pose and Core ML are the preferred Apple-native foundations for capture, candidate segmentation and detector execution. The free perception lane packages the MIT-licensed WASB-SBDT three-frame sports-ball model, evaluates source-resolution tiles and applies purpose-built single-ball temporal association. SAM-style models are labelling aids rather than an iPhone runtime dependency. Impact-like audio is preferred for timing, with body motion as a fallback when audio is absent or unreadable.

## Release gate

Release confidence requires more than compilation:

- clean watchOS build;
- simulator state review;
- real Apple Watch Ultra Action Button validation;
- permission-denied behaviour;
- round persistence and recovery after termination;
- workout start, recovery and end behaviour;
- accessibility and small-screen review;
- confirmation of signing, archive and App Store state.
