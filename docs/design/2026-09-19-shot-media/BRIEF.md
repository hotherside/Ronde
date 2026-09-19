# Ronde shot-media exploration

19 September 2026. Requested by the owner in this design session. Starting source: `codex/retire-watch-ios-only` at `17cbc55`; the shared checkout subsequently advanced to `main` at `d9b405c`. The concepts and follow-up refinement remain local, uncommitted HTML work; native implementation and hosted services are unchanged.

## Intent and review agenda

Ronde should help golfers turn recordings from a round or range visit into their best shot clips, then trace, edit and export those clips for social posts. The owner requested three substantially different visual directions for review before a native redesign.

The owner selected **Clubhouse as the design foundation**, with substantial further refinement required. The accepted Studio intent is to review a full 10–20-minute recording, bookmark points and turn those bookmarks into a list of smaller, source-linked shots without altering the original. A bookmark marks source time; a keeper is a favourite shot. See [ADR 0013](../../context/decisions/0013-clubhouse-and-bookmarked-recording-studio.md).

Review the refined recording-to-shots interaction and connected shot editor next. Exact extraction defaults and the native data migration remain proposals; the current native importer still accepts a single video up to 60 seconds.

## Concept directions

- Clubhouse: selected foundation. Warm chalk and deep green, editorial session covers and a personal collection of keepers; the recording Studio now leads the refinement.
- Cutroom: off-white and cobalt, precise contact sheets and a recording-to-shot workspace.
- Fieldwork: pale sand and vermilion, expressive typography and a rapid one-at-a-time review queue.

## Shared exploration contract

- Proposed model: Session contains Recordings; each Recording retains manual Bookmarks and source-linked Shots. Optional future moment suggestions can feed the same review flow. Favourite Shots are Keepers; each Shot can have reversible Edits and Export derivatives.
- Prototype default for review: five seconds before and five seconds after each bookmark, adjustable per bookmark and clamped to the source. Repeated extraction skips bookmarks that already have a shot, preserving existing edits. Open that existing shot to refine it. These precise rules are implementation proposals, not separately approved product decisions.
- Finding a possible shot and tracking its ball are independent states. A golfer may confirm an untracked shot and still trim/export it. No numerical distance.
- Sources remain intact and on device. Skip is reversible and does not delete source footage. Favourite is a flag, not another media copy.
- Compact layouts use one focused screen; expanded layouts keep the collection and selected media together. Resizing should preserve selection and draft state.
- All sample people, places, counts, imagery, segmentation and traces are fictional. These prototypes do not run inference, record camera video, encode videos or post externally.
- Generated imagery is for design review, never tracker validation. Existing native accuracy and physical-device gates remain unresolved.

## Prototype integration

Each direction is a standalone HTML page. Review wrapper changes iframe width without reloading the selected concept. Shared photographic assets will be `assets/range.png` and `assets/course.png`. Do not depend on private user footage. Optional `window` message: `{ type: 'ronde:navigate', view: 'sessions' | 'shots' | 'studio' }` changes the visible screen without losing draft/selection state. Use only these messages from the same origin.

For review: iPhone at 393px, Duo compact at 393px / expanded at 760px, iPad at 1120px. These are illustrative CSS viewports, not Apple hardware dimensions or native system-bar simulations. The native Duo experience needs the corresponding SDK/runtime and actual pose/safe-area validation.
