# From a recording to a keeper

**Status:** Clubhouse selected as the design foundation on 19 September 2026, with further refinement required. The owner accepted a recording Studio for bookmarking full 10–20-minute videos and creating smaller source-linked shots. Detailed model, extraction defaults and native migration remain proposals. [ADR 0013](../../context/decisions/0013-clubhouse-and-bookmarked-recording-studio.md)

**Subsequent implementation:** the owner authorised execution using Clubhouse, Cutroom and native Liquid Glass. [ADR 0014](../../context/decisions/0014-native-recording-studio-and-source-linked-shots.md) and the product contract now own the native behaviour. The proposal below is retained as exploration history.

## What the owner asked for

Make Ronde a distinctive golf media companion for people who set a phone down and record themselves: find useful shots inside recordings, keep the best, add a trace, make quick edits, and export for social posts. After reviewing three HTML directions, the owner endorsed Clubhouse's concept and clarified that Studio must support bookmarking a long recording, then breaking it into a reusable shot list. iPhone, iPad and Duo continuity remains part of the design review.

## Accepted workflow intent and proposed detail

1. Open a full source recording, including the intended 10–20-minute session footage, in Recording Studio.
2. Scrub or play the source and add manual bookmarks at useful points. Each bookmark stores a source timestamp, not a favourite or a claim of detected impact.
3. Review the ranges around those bookmarks and create a batch of source-linked Shots. The original remains intact.
4. Review the resulting shot list, favourite the best and open an individual shot to trim, format or add an available observed trace or a separately labelled manual trace.
5. Export a derivative, then return to the source recording or Shots collection.

For the HTML refinement, propose **five seconds before and five seconds after** each bookmark, adjustable per bookmark and clamped to the source boundaries. Repeating extraction skips bookmarks that already have a shot, preserving existing edits and avoiding duplicates. Open the existing shot for further refinement. The owner's reference to adding or removing five seconds establishes quick range adjustment as the intent; it does not separately approve these exact defaults or repeat-extraction semantics.

Manual clipping must work without automatic suggestions or a successful ball track. Optional future detection can reduce searching, but the golfer decides which shots are worth keeping. It cannot claim to judge the best swing.

## Proposed local model

| Record | Relationship | Purpose and key fields |
| --- | --- | --- |
| Session | One to many Recordings | The outing: ID, title, date, optional user-entered place, ordered recording IDs. |
| Recording | Belongs to one Session | Immutable local source: ID, owned relative media reference, duration/timebase, orientation, import/capture date, processing state. |
| Bookmark | Belongs to one Recording | Manual source timestamp, adjustable before/after range and stable ID. Proposed extraction link identifies the resulting Shot. Not an impact observation or favourite. |
| Moment | Optional future suggestion within one Recording | Proposed interval, timing evidence and review state (`pending`, `confirmed`, `skipped`). Does not gate manual bookmarks or clipping. |
| Shot | References one Recording and its source range | Stable reusable selection: ID, optional originating bookmark/suggestion ID, source start/end, optional club/title/note, favourite flag and provenance. Does not copy the source. |
| Edit | Belongs to one Shot | Versioned reversible trim, fit/crop transform, chosen output canvas, audio and trace selection. |
| Trace | Belongs to one Shot | `unavailable`, source-timed observed samples, or separately authored manual geometry. Display state is independent of shot confirmation. |
| Export | References an Edit snapshot | Disposable generated file plus creation time and format. An export never mutates the source or reruns analysis. |

**Keepers are favourite Shots, not bookmarks or another table of videos.** Bookmarking, creating a shot and favouriting that shot are separate operations. A clip can have several output edits without duplicating the source. A later montage would reference several Shots; a full reel composer is outside this refinement.

Automatic acceptance remains governed by the current evidence gate. An audio/motion event can create a proposed Moment; it cannot silently become an observed ball track. The current native app still accepts a single video up to 60 seconds and does not expose long-recording bookmarks or batch extraction. Implementing this accepted future direction requires a reviewed migration from the existing archive, bounded media work and new validation.

## States the redesign must handle

- Importing, analysing and ready states belong to individual recordings. One failed recording must not block the session.
- Manual bookmark extraction, optional candidate segmentation and ball tracking have separate states; the latter two cannot block manual clipping.
- Boundary bookmarks produce valid source-clamped windows. Repeating batch creation must not silently duplicate shots; the exact existing-shot refinement behaviour remains to be reviewed.
- A source remains available when no moment is detected. Let the golfer scrub and mark their own shot.
- Skip is reversible and retains source footage. Removing a keeper changes the favourite flag only.
- Saving an edit can fail; preserve the draft and offer retry. Deletion of a source that has dependent shots requires a clear impact summary.
- Missing local media is different from an empty library. Metadata sync does not imply video backup or cross-device source availability.

## Design selection

| Direction | What to evaluate | Trade-off |
| --- | --- | --- |
| Clubhouse, selected foundation | Refine the warm, photographic identity and make the recording-to-shots Studio clear and fast. | Needs stronger batch-review density without losing its character. |
| Cutroom | Can a golfer move from recording to selected clips with fewer taps and less scrubbing? | More functional, with less emotional character. |
| Fieldwork | Does a large moment and a clear Keep/Skip decision make reviewing footage feel quick? | Sequential review makes side-by-side comparison harder. |

The owner selected Clubhouse's overall concept, not a final pixel-level design. Cutroom and Fieldwork remain comparison explorations. Refine Clubhouse's recording Studio and connected shot editor before treating its interaction details as settled.

## Adaptive design

On compact screens use focused navigation. On a wider window preserve session context and the selected shot beside the studio. On iPad reveal two or three panes only when usable space permits, and collapse them coherently in smaller windows. [Apple split views](https://developer.apple.com/design/human-interface-guidelines/split-views)

For Duo, Apple specifies vertical bars on the outer display and inner landscape, and horizontal bars in inner portrait. In split layouts, editing controls belong to the detail column; collection controls stay with the collection. Partly folded layouts move critical controls clear of the crease. A permanent centre gutter when flat is not appropriate. The separate pose study is Ronde's interpretation of that guidance. [Duo bars](https://developer.apple.com/videos/play/tech-talks/111462/), [adaptive layouts](https://developer.apple.com/videos/play/tech-talks/111463/), [Duo HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)

Preserve selection, navigation, draft edits and playback position during resizing and display changes. Use container geometry, safe areas and system reserved-region behaviour in native code. Do not route solely by device name. Apple now lists Xcode 27.1 beta for Duo development. This session checked documentation and HTML only, not that SDK, Simulator, signed devices or folding hardware. [Preparing an app](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo), [developer hub](https://developer.apple.com/iphone-duo/)

## Next gate

Review the refined Clubhouse journey from a long source through bookmarks to a shot list and individual edits, including boundary windows and repeated extraction. Then agree the first native slice, migration and long-video performance gates. Automatic moment proposals follow the manual workflow; reliable ball tracing remains an independent perception project and release gate.
