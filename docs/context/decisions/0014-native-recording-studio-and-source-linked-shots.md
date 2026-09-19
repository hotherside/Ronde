# 0014: Native Recording Studio and source-linked Shots

**Status:** Implemented and Simulator-verified; source delivery in [PR #12](https://github.com/hotherside/Ronde/pull/12); signed-device and distribution gates remain

**Date:** 19 September 2026

## Context and source

ADR 0013 selected Clubhouse as the design foundation and described a manual recording-to-shots workflow, while leaving the native migration as a later gate. The owner then explicitly authorised native execution, combining Clubhouse, Cutroom's Studio controls and Liquid Glass, with Astra owning design and orchestration. Implementation `6fdb6a6` was prepared on `codex/clubhouse-native-studio` from `d9b405c` and is recorded in PR #12. The Apple Watch product remains retired by ADR 0012. [Current State](../CURRENT_STATE.md#verification) records the completed local build, media and Simulator UI checks; signed-device and release evidence remain separate.

## Decision

Adopt the Clubhouse foundation with Cutroom's focused editing vocabulary and native SwiftUI Liquid Glass controls. Present the local library as Sessions containing Recordings and source-linked Shots, with favourites identifying Keepers.

Recording Studio accepts a manual source recording up to 20 minutes from Photos, Files or the native camera. It keeps the app-owned original intact and lets the golfer inspect the full source in a source-time player with sparse generated thumbnails. Derived Shot frame inspection is bounded to the original clip plus five seconds on either side. A bookmark is a person-authored source timestamp, separate from a favourite and separate from ball-flight evidence.

Each bookmark starts with a five-second window before and after its timestamp. Each side can be changed in five-second increments between 0 and 60 seconds and is clamped to the source boundaries. Batch creation makes source-linked Shots that retain the recording's local source URL, group identity, bookmark identity and source clip range. Repeating creation skips an already extracted bookmark and preserves that Shot's existing edits. Removing the original is blocked while linked Shots remain.

Shot Studio retains the original source and offers reversible Trim, Trace and Format controls. The four output canvases remain Original, 9:16 vertical, 1:1 square and 16:9 landscape. A manual recording or source-linked Shot does not need a successful automatic ball track to be useful or shareable. Derived Shots start untraced and support manual annotation; automatic moment suggestions, automatic analysis of these long-source Shots and hands-free long-session capture remain deferred. This slice makes no new accuracy claim for the existing observed-only tracer.

## Alternatives and consequences

An automatic-suggestion-first flow was rejected because it would make manual review depend on unresolved perception accuracy. Copying each extracted Shot was rejected because source-linked ranges preserve the original and avoid duplicate media. A separate archive envelope was rejected because the existing account-scoped archive can remain compatible while adding optional group, bookmark and source-link fields.

The result gives the native app a coherent Sessions → Recordings → Bookmarks → Shots/Keepers journey and a practical manual path for long recordings. The archive and range contract passed unit/media checks, all six iPhone UI journeys passed, and the Session/recording journeys passed on iPad and Duo Simulators. Representative long-source playback, memory, thermal behaviour, camera permissions and signed-device reliability still require hardware verification. Native controls use actual system Liquid Glass on iOS 26+ with an earlier-system fallback; media and content cards retain opaque, readable surfaces.
