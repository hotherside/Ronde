# Ronde product contract

**Status:** current working contract

**Reviewed:** 19 September 2026

## Product

Ronde is a local-first universal iPhone/iPad media library for a golfer's shot videos. It helps golfers collect and organise their shots, inspect each swing in a focused studio, create useful clips and show a ball path only when the uploaded frames support a defensible track.

The essential loop is:

1. Import or capture a golf-shot video.
2. Store the original in the golfer's private local library.
3. Search, favourite and add useful shot context.
4. Review the shot with source-frame controls and an honest tracer state.
5. Trim and format a non-destructive derivative.
6. Export or share the edited shot without changing the original.

## Experience rules

- Ronde is an iPhone/iPad product. It has no watchOS app, round counter, Action Button workflow or HealthKit workout.
- The app opens into one Shot library with search and favourites. Settings are a sheet; dashboard metrics are not a primary surface.
- Use a neutral, light workspace with large media, clear typography and a small number of grouped actions.
- Import is a labelled toolbar or empty-state action. A successful import opens its studio as soon as the video is safely stored; analysis continues in that shot's state.
- The current MVP accepts one shot video up to 60 seconds. Keep the source intact and save reversible trim, format and overlay settings separately.
- The Shot Studio combines an aspect-fitted player, pause/resume, source-frame stepping, scrubbing, a thumbnail trim timeline and sharing. Export remains available when no automatic trace is found.
- Social export offers original aspect, 9:16, 1:1 and 16:9 canvases. Fit the entire source without stretching or hiding the ball through an implicit crop. Preview and export share the same transform. Encode a local H.264 MP4 with available source audio; timing is rebased to the selected source range.
- Each account's local library supports search, favourites, optional course/range, club and notes. Failed saves remain visible and retryable. An unreadable archive must never silently become a writable empty library.
- Manual trace editing uses a local draft over the fitted source. Cancel discards changes; Save persists a separately labelled annotation. The user can remove it and return to the original automatic evidence.
- Impact analysis is an internal timing input for ball acquisition and tracer reveal. The golfer is not asked to identify a start point before automatic review can appear.
- Range Session and Live Review foundations remain dormant future work. They are not promised current workflows. If long-session segmentation returns, a proposed event may become an automatic shot only after target-golfer impact and a stable, time-aligned golf-ball launch agree.
- The app must never fabricate an automatic tracer. A video without enough ball-specific observations remains playable and says `Ball flight not tracked`; audio, body motion, generic Vision motion and fixed fallback geometry cannot create a visible automatic line.
- Uploaded files are processed using their own presentation timestamps and orientation. No specific recording frame rate is required; lower temporal or spatial quality may reduce tracking confidence and result in no tracer.
- Native Vision trajectory analysis may be used as a constrained diagnostic baseline, but generic moving-shape points cannot accept a real shot, enable a tracer or earn an `Observed` golf-ball label. An automatic tracer may appear only when the packaged sports-ball model produces a temporally consistent post-impact track.
- The active studio's automatic overlay contains only accepted observed samples with their source presentation timestamps. It stops when those samples end. It does not show modelled landing, inferred full-flight continuation or numerical carry.
- Extrapolation remains experimental analysis code and archived data, not the active studio presentation. Reintroducing it requires a new decision backed by labelled footage and calibrated ground truth.
- A person may annotate the path with a separately labelled `Manual trace`. It is not automatic observation or measured distance. Shared videos preserve this provenance label.
- Playback and export consume the same saved geometry and source timing. Export does not rerun detection and never overwrites the original.
- Raw media, tracer geometry and analysis stay on-device for MVP. Supabase may store the signed-in profile and lightweight private library metadata such as title, date, place, club, favourite state and evidence provenance. It must not receive raw video, local file paths, analysis frames, analytics or background location.

## Platform and technical boundary

- One universal SwiftUI target supports iPhone and iPad.
- The library archive is scoped to the current Apple account on the device. Supabase Auth and row-level security protect corresponding private metadata rows.
- AVFoundation owns source playback, capture foundations and local export. Vision and Core ML provide on-device analysis foundations.
- The free perception lane packages the MIT-licensed WASB-SBDT three-frame sports-ball model, evaluates source-resolution tiles and applies purpose-built single-ball temporal association. Impact-like audio is preferred for timing, with body motion as a fallback when audio is absent or unreadable.
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
