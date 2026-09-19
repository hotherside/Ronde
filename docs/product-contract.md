# Ronde product contract

**Status:** current working contract

**Reviewed:** 19 September 2026

## Product

Ronde is a local-first universal iPhone/iPad media library for a golfer's shot videos. It helps golfers collect and organise their shots, inspect each swing in a focused studio, create useful clips and show a ball path only when the uploaded frames support a defensible track.

The essential loop is:

1. Import or capture a golf-shot video or a longer manual recording.
2. Store the original in the golfer's private local Sessions library.
3. Open an imported clip shorter than 20 seconds directly in Shot Studio. For longer Recordings, choose a clip window, bookmark useful source times and create source-linked Shots first.
4. Search, favourite Keepers and add useful shot context.
5. Review a Shot with source-frame controls and an honest tracer state.
6. Trim and format a non-destructive derivative, then export or share it without changing the original source.

## Implemented native direction

On 19 September 2026, the owner selected **Clubhouse as the design foundation**, with Cutroom's focused editing vocabulary and native Liquid Glass controls. The local native slice now lets a golfer work through Sessions → Recordings → Bookmarks → source-linked Shots, with favourites identifying Keepers. A recording can be imported or captured up to 20 minutes, reviewed against its original source, and turned into a batch of smaller Shots without copying or mutating that source. [ADR 0013](context/decisions/0013-clubhouse-and-bookmarked-recording-studio.md) records the historical design selection; [ADR 0014](context/decisions/0014-native-recording-studio-and-source-linked-shots.md) records the implemented contract.

The long-recording surface is **Choose shots**, separate from Shot Studio. Each session saves a default bookmark window, initially five seconds before and after its source time, with ±5/±10-second presets and five-second adjustments from 0 to 60 seconds on either side. New recordings in that session inherit the window. New bookmarks apply it and clamp to the source; existing bookmark cuts remain unchanged. Repeating batch creation skips an already extracted bookmark and preserves the existing Shot's edits. Automatic moment suggestions remain deferred. Frame inspection in a derived Shot and its manual trace editor is limited to the bookmarked clip plus five seconds on either side, retaining absolute source times. [ADR 0018](context/decisions/0018-clip-first-tracing-and-correction.md) records the latest flow decision.

## Current native experience rules

- Ronde is an iPhone/iPad product. It has no watchOS app, round counter, Action Button workflow or HealthKit workout.
- The app opens into one Session library with search and favourites. Sessions expose their Recordings and source-linked Shots; Keepers are favourites. Settings are a sheet; dashboard metrics are not a primary surface.
- Use a neutral, light workspace with large media, clear typography and a small number of grouped actions.
- Import is a labelled toolbar or empty-state action. A successful import opens its Recording Studio or Shot Studio as soon as the video is safely stored; analysis is not required for a manual recording or source-linked Shot.
- Recording imports accept one source up to 20 minutes from Photos, Files or the native camera. Sources shorter than 20 seconds open directly in Shot Studio without bookmarks or an analysis wait; exactly 20 seconds and longer use Choose shots. The legacy one-shot analysis path retains its 60-second policy. The original source remains intact and source-linked Shots share that local source while saving reversible edits separately.
- Recording Studio combines full-source playback, source-time scrubbing, generated thumbnails, manual bookmarks, clamped five-second window adjustments and batch Shot creation. Shot Studio combines an aspect-fitted player, pause/resume, source-frame stepping, scrubbing, Trim/Trace/Format tabs and sharing. Export remains available when no automatic trace is found.
- Social export offers original aspect, 9:16, 1:1 and 16:9 canvases. Fit the entire source without stretching or hiding the ball through an implicit crop. Preview and export share the same transform. Encode a local H.264 MP4 with available source audio; timing is rebased to the selected source range.
- Each account's local library supports search, favourites, optional course/range, club and notes. Failed saves remain visible and retryable. An unreadable archive must never silently become a writable empty library.
- The recording, bookmark and source-link fields are additive to the existing account-scoped archive. Legacy archives remain readable and continue to represent their existing Shot rows without requiring a migration envelope.
- Manual trace editing uses a local draft over the fitted source. Cancel discards changes; Save persists a separately labelled annotation. The user can remove it and return to the original automatic evidence.
- Impact analysis is an internal timing input for ball acquisition and tracer reveal. The golfer is not asked to identify a start point before automatic review can appear.
- Shot Studio has one primary `Trace shot` action for a selected clip of at most 20 seconds. It searches the selected interval for impact timing and accepted ball observations, then follows a detected ball point with EdgeTAM on-device. No guessed point is used when acquisition fails. `Correct trace` offers source-frame ball selection/retracking or a drawn/adjustable path. Broader app redesign remains separate.
- Point-assisted results persist separately from automatic evidence and manual annotation. Save actual source-pixel observations, source indices/timestamps, empty-frame gaps and model/policy provenance. Preview and export keep gaps as separate strokes and label the selected-point origin; missing flight, landing and distance are not invented. Cancellation preserves the prior saved trace, and processing limits remain explicit.
- Newly created source-linked Shots start untraced and support the same explicit `Trace shot` action, correction and export as short imports. Whole-recording automatic segmentation and moment suggestions remain further work.
- Range Session and hands-free Live Review foundations remain dormant future work. The implemented Recording Studio is manual and does not claim automatic long-session segmentation, shot suggestions or hands-free capture.
- The app must never fabricate an automatic tracer. A video without enough ball-specific observations remains playable and says `Ball flight not tracked`; audio, body motion, generic Vision motion and fixed fallback geometry cannot create a visible automatic line.
- Uploaded files are processed using their own presentation timestamps and orientation. No specific recording frame rate is required; lower temporal or spatial quality may reduce tracking confidence and result in no tracer.
- Native Vision trajectory analysis may be used as a constrained diagnostic baseline, but generic moving-shape points cannot accept a real shot, enable a tracer or earn an `Observed` golf-ball label. An automatic tracer may appear only when the packaged sports-ball model produces a temporally consistent post-impact track.
- The active studio's automatic overlay contains only accepted observed samples with their source presentation timestamps. It stops when those samples end. It does not show modelled landing, inferred full-flight continuation or numerical carry.
- Extrapolation remains experimental analysis code and archived data, not the active studio presentation. Reintroducing it requires a new decision backed by labelled footage and calibrated ground truth.
- A person may draw a path or adjust its points as a separately labelled `Manual trace`. Preview and export use the saved normalised path. It is not automatic observation or measured distance. Shared videos preserve this provenance label; corrections do not upload footage or train models in the background.
- Playback and export consume the same saved geometry and source timing. Export does not rerun detection and never overwrites the original.
- Raw media, tracer geometry and analysis stay on-device for MVP. Supabase may store the signed-in profile and lightweight private library metadata such as title, date, place, club, favourite state and evidence provenance. It must not receive raw video, local file paths, analysis frames, analytics or background location.

## Platform and technical boundary

- One universal SwiftUI target supports iPhone and iPad.
- The library archive is scoped to the current Apple account on the device. Supabase Auth and row-level security protect corresponding private metadata rows.
- AVFoundation owns source playback, capture foundations and local export. Vision and Core ML provide on-device analysis foundations.
- The implemented Clubhouse/Cutroom surface uses native SwiftUI Liquid Glass controls around warm opaque content. `RecordingImportView` captures import ownership before Photos, Files or camera work; `RecordingStudioView` persists bookmarks and source-linked Shots through the existing account-scoped archive.
- The free perception lane packages the MIT-licensed WASB-SBDT three-frame sports-ball model, evaluates source-resolution tiles and applies purpose-built single-ball temporal association. Impact-like audio is preferred for timing, with body motion as a fallback when audio is absent or unreadable.
- The tracing pipeline uses packaged WASB observations for automatic seed discovery and the separately packaged Apache-2.0 EdgeTAM Core ML pipeline for propagation. User-selected seeds remain a fallback with distinct provenance. EdgeTAM verifies local component/constant identities and never downloads models or sends media to a cloud service. WASB's detector and eligibility gates remain unchanged. [ADR 0017](context/decisions/0017-opt-in-on-device-ball-tracking.md) records the initial integration, with its entry flow superseded by ADR 0018. Physical-device stability and representative accuracy remain release gates.
- In-app capture foundations target a stable rear-camera view at 60 fps, settling and locking focus/exposure where hardware permits. A complete hands-free capture loop is not a current product claim.
- Reviewer media processing remains confidence-gated. Physical-device performance and model quality are release gates.

## Release gate

Release confidence requires more than compilation:

- representative labelled golf footage with acquisition recall, false-tracer rate, point error, visible-track coverage and latency reported separately;
- frame-by-frame verification of rendered lines and trimmed exports on a signed iPhone and iPad;
- first/repeat Apple login, cold offline launch, two-account isolation and metadata failure/reconciliation checks;
- camera, microphone, photo-library and motion permission-denied behaviour;
- accessibility, compact landscape, large text and iPad multitasking review;
- confirmation of signing, archive, TestFlight compliance/internal access and App Store state.

The earlier Apple Watch shot-counter contract was retired on 19 September 2026 by [ADR 0012](context/decisions/0012-ios-ipad-only-product.md). Its code and build target are not part of the current product.
