# Ronde product contract

**Status:** current working contract

**Reviewed:** 30 August 2026

## Product

Ronde is an Apple Watch golf shot counter and a local-first iPhone/iPad shot reviewer. The Watch remains the independent core product for keeping an honest score without repeatedly handling a phone. The reviewer helps golfers build a private media library, inspect range swings, create useful clips and review a ball path only when the uploaded frames support a defensible track.

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
- The reviewer uses Sign in with Apple as its only account method. Account access must never become a prerequisite for the independent Watch counter.
- The primary reviewer navigation is Home, Library and Profile. Import is a labelled toolbar or empty-state action, not a floating action button.
- Home and Profile summaries use only saved review data. Production empty states show zero or unavailable values rather than fixture statistics.
- The Library persists each signed-in account's local reviews separately and supports search, favourites, optional place/course, club and notes.
- The reviewer MVP accepts one shot video up to 60 seconds. It retains the full source range, opens directly into an automatically playing video-first Shot Review and does not expose long-session slicing, candidate classification or shot-confirmation theatre.
- Impact analysis is an internal timing input for ball acquisition and tracer reveal. The golfer is not asked to identify a start point before an automatic review can appear.
- Range Session and Live Review foundations remain dormant future work. If long-session segmentation returns, a proposed event may become an automatic shot only after target-golfer impact and a stable, time-aligned golf-ball launch agree.
- Live Review may use a temporary rolling capture buffer for hands-free one-shot feedback. It retains the candidate clip only after an impact-like event, plays it automatically after post-roll and processing, and discards unrelated buffer segments.
- The MVP must never fabricate an automatic tracer. A short review without enough ball-specific observations remains playable and says `Ball flight not tracked`; audio, body motion, generic Vision motion and fixed fallback geometry cannot create a visible automatic line.
- Uploaded files are processed using their own presentation timestamps and orientation. No specific recording frame rate is required; lower temporal or spatial quality may reduce tracking confidence and result in no tracer.
- Native Vision trajectory analysis may be used as a constrained diagnostic baseline, but generic moving-shape points cannot accept a real shot, enable a tracer or earn an `Observed` golf-ball label. A one-shot review may show an automatic tracer only when the packaged sports-ball model produces a temporally consistent post-impact track. Long-session shot acceptance additionally requires target-golfer association.
- A confidence-gated, source-timed two-dimensional ball track may seed a perspective-aware ballistic presentation fit. Around impact, a separate compact-bright-object disappearance check may anchor the launch to the visible stationary ball when that source-frame evidence is unique; ambiguity must fail closed. The fit may estimate from that observed launch anchor through the first tracked mid-air point and forwards through a screen-space apex to a bounded landing. Detector-to-model join residual decays down-range instead of being carried unchanged to landing; lateral continuation remains inside a corridor derived from the robust observed displacement, and a displayable landing must remain below the fitted horizon, above the launch point and inside the safe frame. Playback reveals one continuous, smoothly tapered solid-purple ribbon from impact towards landing. The observed causal portion follows source timestamps without reaching a future ball position; fitted launch and continuation portions use subtly lower opacity and explicit estimate labels rather than dashes, seams or a separate reveal order. The apex is visibly marked only when the reveal reaches it. A generic trajectory or an unanchored projection cannot seed this path.
- If a short source ends before the modelled landing, playback and export preserve the original model timing through apex plus the sampling-derived causal lag, capped at 50 ms. Only the post-apex descent may be compressed, and the completed-path hold may not exceed 120 ms. If the source cannot contain the modelled apex plus lag, landing and carry remain hidden rather than making the tracer lead the ball. This supersedes uniform whole-continuation compression and must not change detector timestamps, fitted geometry, modelled carry or the distinction between observation and estimation.
- A person may rescue or correct a path with the assisted editor. User-authored geometry must be labelled `Manual trace` and must not be presented as automatic observation.
- Playback and traced-video export use the same saved geometry. Export does not rerun analysis, and the original source remains unchanged.
- When multiple similarly plausible perspective fits pass the evidence gate, Ronde may display their rounded carry spread in metres as `Model carry` with `Estimate · uncalibrated`. It is broad directional guidance, not measured distance or launch-monitor precision. Precise carry and physical apex height remain later experiments requiring calibration and known ground truth.
- Reviewer media, tracer geometry and analysis stay on-device for MVP. Supabase may store the signed-in profile and lightweight private library metadata such as title, date, place, club, favourite state, evidence provenance and broad supported carry range. It must not receive raw video, local file paths, analysis frames, remote round storage, analytics or background location.

## Platform boundary

- The watchOS application is the independent core shot-counter product.
- The iOS target is a universal iPhone/iPad Shot Reviewer and also remains the packaging companion required by the watch bundle relationship.
- The reviewer archive is scoped to the current Apple account on the device. Supabase Auth and row-level security protect the corresponding private metadata rows.
- Reviewer media processing uses Apple on-device frameworks where available, with confidence and unsupported-input states exposed honestly. Physical-device performance and model quality remain validation gates.
- SwiftData owns local round history.
- HealthKit owns the optional golf workout session.
- Core Location and the bundled Sydney course library support nearby-course selection.
- App Intents supplies the Action Button-compatible shot action, but real hardware configuration and invocation require manual verification.
- AVFoundation, Vision human-body pose and Core ML are the preferred Apple-native foundations for capture, candidate segmentation and detector execution. The free perception lane packages the MIT-licensed WASB-SBDT three-frame sports-ball model, evaluates source-resolution tiles and applies purpose-built single-ball temporal association. SAM-style models are labelling aids rather than an iPhone runtime dependency. Impact-like audio is preferred for timing, with body motion as a fallback when audio is absent or unreadable.
- In-app reviewer capture targets a stable rear-camera view at 60 fps, settles then locks focus and exposure where hardware permits, and guides the golfer to include the address position and expected flight corridor. Higher-frame-rate imports remain eligible; 240 fps is an optional quality input rather than a requirement.

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
