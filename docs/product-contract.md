# Ronde product contract

**Status:** current working contract

**Reviewed:** 7 September 2026

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
- The reviewer opens into one Shot library with search and favourites. Settings are a sheet; Home/Profile dashboards and trace-rate charts are not primary product surfaces.
- Use a neutral, light workspace with large media, clear typography and a small number of grouped actions. The reference is the focus of Linear and Notion, adapted to native iOS and iPadOS, rather than their literal branding.
- Import is a labelled toolbar or empty-state action. A successful import opens its own editor as soon as the video is safely stored; analysis continues in that shot's state.
- The MVP accepts one shot video up to 60 seconds. Keep the source intact and save reversible trim, format and overlay settings separately.
- The Shot studio combines an aspect-fitted player, pause/resume, source-frame stepping, scrubbing, a thumbnail trim timeline and sharing. Export is available with or without a trace.
- Social export offers original aspect, 9:16, 1:1 and 16:9 canvases. Fit the entire source without stretching or hiding the ball through an implicit crop. Preview and export share that transform. Encode a local H.264 MP4 with available source audio; timing is rebased to the selected source range.
- Each account's local library supports search, favourites, optional course/range, club and notes. Failed saves remain visible and retryable. An unreadable archive must never silently become a writable empty library.
- Manual trace editing uses a local draft over the fitted source. Cancel discards changes; Save persists a separately labelled annotation. The user can remove it and return to the original automatic evidence.
- Impact analysis is an internal timing input for ball acquisition and tracer reveal. The golfer is not asked to identify a start point before an automatic review can appear.
- Range Session and Live Review foundations remain dormant future work. If long-session segmentation returns, a proposed event may become an automatic shot only after target-golfer impact and a stable, time-aligned golf-ball launch agree.
- Live Review may use a temporary rolling capture buffer for hands-free one-shot feedback. It retains the candidate clip only after an impact-like event, plays it automatically after post-roll and processing, and discards unrelated buffer segments.
- The MVP must never fabricate an automatic tracer. A short review without enough ball-specific observations remains playable and says `Ball flight not tracked`; audio, body motion, generic Vision motion and fixed fallback geometry cannot create a visible automatic line.
- Uploaded files are processed using their own presentation timestamps and orientation. No specific recording frame rate is required; lower temporal or spatial quality may reduce tracking confidence and result in no tracer.
- Native Vision trajectory analysis may be used as a constrained diagnostic baseline, but generic moving-shape points cannot accept a real shot, enable a tracer or earn an `Observed` golf-ball label. A one-shot review may show an automatic tracer only when the packaged sports-ball model produces a temporally consistent post-impact track. Long-session shot acceptance additionally requires target-golfer association.
- The active studio's automatic overlay contains only accepted observed samples with their source presentation timestamps. It stops when those samples end. It does not show modelled landing, inferred full-flight continuation or numerical carry.
- Extrapolation remains experimental analysis code and archived data, not the active studio presentation. Reintroducing it requires a new decision backed by labelled footage and calibrated ground truth; see ADR 0011, which supersedes the active presentation choices in ADRs 0007, 0008 and 0010.
- A person may annotate the path with a separately labelled `Manual trace`. It is not automatic observation or measured distance. Shared videos preserve this provenance label.
- Playback and export consume the same saved geometry and source timing. Export does not rerun detection, and it never overwrites the original.
- Reviewer media, tracer geometry and analysis stay on-device for MVP. Supabase may store the signed-in profile and lightweight private library metadata such as title, date, place, club, favourite state and evidence provenance. It must not receive raw video, local file paths, analysis frames, remote round storage, analytics or background location.

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
