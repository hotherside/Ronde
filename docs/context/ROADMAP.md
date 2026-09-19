# Roadmap

## Selected design foundation: Clubhouse with Cutroom editing

The owner selected Clubhouse from the [19 September concepts](../design/2026-09-19-shot-media/README.md), then the local native slice implemented its recording-to-shots direction with Cutroom's focused editing vocabulary and native Liquid Glass controls. Sessions contain Recordings, manual Bookmarks and source-linked Shots; favourites identify Keepers while the original recording remains intact. Manual recordings accept up to 20 minutes. Each bookmark starts at ±5 seconds, adjusts in 5-second increments from 0 to 60 seconds per side, clamps to the source and can be batch-extracted once without overwriting existing Shot edits. [ADR 0013](decisions/0013-clubhouse-and-bookmarked-recording-studio.md) is the historical design selection; [ADR 0014](decisions/0014-native-recording-studio-and-source-linked-shots.md) records the implementation contract.

Automatic moment suggestions remain deferred. Manual selection works without suggestions or a successful ball track. Derived-shot frame inspection is bounded to the bookmarked clip plus five-second handles; Recording Studio uses sparse thumbnails across the full source. Implementation `6fdb6a6` is recorded in [PR #12](https://github.com/hotherside/Ronde/pull/12); Simulator checks are recorded in Current State and signed-device validation is the next gate.

## Now: earn trust in the media loop

- Extend the passing two-clip physical iPhone repeat to repeated use, cancellation, peak memory and sustained thermals. No matching main-app termination report was retrieved for the owner's 10% crash, so the original cause remains unresolved. The CPU/Neural Engine tracking, short export/decode and archive check completed; memory pressure remains a hypothesis. Check the new clip-first flow: below-20-second imports, per-session bookmark windows, one Trace shot action, automatic-seed acquisition and manual correction. [ADR 0018](decisions/0018-clip-first-tracing-and-correction.md) supersedes the earlier point-selection-first UI; automatic-seed accuracy must be scored separately from supplied-point benchmarks.

- Continue functionality work from the authorised Clubhouse/Cutroom correction. The owner rejected the first native translation on 19 September; `codex/concept-fidelity` removes marketing headers, restores compact media grids and strengthens typography and editing hierarchy. Source delivery was then authorised with no more app testing. Use the populated native captures for reference, and keep a repeat physical-iPhone UAT pass as a separate device gate.

- Run a signed-iPhone matrix for the locally implemented Sessions/Recording Studio/Shot Studio slice for Photos/Files/camera recording import up to 20 minutes, source preservation, bookmarks, boundary clamping, duplicate-safe batch extraction, pause/resume, frame stepping, trim, all four output canvases, audio, cancellation and native sharing. Include slow-motion/VFR, rotated portrait, no-audio and unsupported input.
- Finish independent review of the new two-source tracer references, especially blurred launch and faint late flight, and obtain the remaining rejected owner clips. The local benchmark now separates candidate recall, wrong-object association, missing spans and source-time rendering; the initial labels are agent-reviewed, not human-verified ground truth. Keep the automatic studio line observed-only. See [ADR 0015](decisions/0015-source-timed-tracer-benchmark.md).
- Keep default WASB acquisition and eligibility unchanged while validating the owner-authorised `Trace shot` pipeline and manual correction inside Ronde. The current scope is tracer-only, without redesign. Test one variable at a time, preserve uncertainty and rerun distractor negatives; more retained points alone are not a success.
- Measure automatic acquisition separately from the passing supplied-seed iPhone check. The phone reached 101/113 daylight and 102/103 night development positions within 12 source pixels in 33.979/38.032 seconds, with twelve daylight misses and the blurred night launch error. Source/model identities, short segmented exports and archive round-trip passed. These provisional known-clip results do not establish held-out accuracy or sustained device safety. See [ADR 0018](decisions/0018-clip-first-tracing-and-correction.md) and the validation ledger.
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
