# Roadmap

## Selected design foundation: Clubhouse with Cutroom editing

The owner selected Clubhouse from the [19 September concepts](../design/2026-09-19-shot-media/README.md), then the local native slice implemented its recording-to-shots direction with Cutroom's focused editing vocabulary and native Liquid Glass controls. Sessions contain Recordings, manual Bookmarks and source-linked Shots; favourites identify Keepers while the original recording remains intact. Manual recordings accept up to 20 minutes. Each bookmark starts at ±5 seconds, adjusts in 5-second increments from 0 to 60 seconds per side, clamps to the source and can be batch-extracted once without overwriting existing Shot edits. [ADR 0013](decisions/0013-clubhouse-and-bookmarked-recording-studio.md) is the historical design selection; [ADR 0014](decisions/0014-native-recording-studio-and-source-linked-shots.md) records the implementation contract.

Automatic moment suggestions remain deferred. Manual selection works without suggestions or a successful ball track. Derived-shot frame inspection is bounded to the bookmarked clip plus five-second handles; Recording Studio uses sparse thumbnails across the full source. The current implementation is uncommitted on `codex/clubhouse-native-studio` at `d9b405c`; Simulator checks are recorded in Current State; signed-device validation is the next gate.

## Now: earn trust in the media loop

- Run a signed-iPhone matrix for the locally implemented Sessions/Recording Studio/Shot Studio slice for Photos/Files/camera recording import up to 20 minutes, source preservation, bookmarks, boundary clamping, duplicate-safe batch extraction, pause/resume, frame stepping, trim, all four output canvases, audio, cancellation and native sharing. Include slow-motion/VFR, rotated portrait, no-audio and unsupported input.
- Label the exact five rejected owner clips before another detector experiment. Separate acquisition misses, wrong-object association, timing error and renderer error. Keep the automatic studio line observed-only.
- Build a consented held-out golf set with varied lighting, phone distance, camera angle, ball colours and distractors. Measure acquisition recall, false-tracer rate, point error in source pixels, visible-track coverage and processing cost. Deterministic tracker tests protect invariants; they do not supply these scores.
- Verify local archive recovery, save failures and two-account import cancellation on hardware. Complete cold offline authentication and durable cloud metadata deletion/reconciliation.

## Next: precision editing and golf-specific perception

- Add an explicit crop/reframe preview with a movable safe area for social output. Current fit canvases deliberately preserve the entire shot.
- Measure long-source playback, thumbnail generation, memory, thermal behaviour and source-frame inspection on representative signed devices. Keep the manual recording path useful without automatic suggestions.
- Evaluate a reproducible, commercially distributable golf-specific training route on the labelled dataset. Keep inference local; verify dataset, code and weight licences before adopting any model. Existing WASB tennis-domain weights remain an experimental baseline.
- Use user-confirmed corrections as opt-in local review evidence. Never label a hand-drawn path as ground truth or upload private footage automatically.
- Test VoiceOver, largest text sizes, compact landscape and iPad split-screen with actual media editing tasks.

## Later: evidence-led expansion

- Reintroduce flight estimation or distance only with calibrated ground truth and a new product decision. A plausible parabola is not measured flight.
- Add optional automatic moment suggestions, hands-free capture or automatic replay only after the manual recording workflow and relevant detection gates earn acceptance.
- Consider cross-device metadata restoration or encrypted media backup only with explicit ownership, retention, cost and deletion design.

This roadmap does not imply measured distance, cloud video recovery or a published App Store build.
