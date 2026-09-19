# Ronde: three shot-media directions

**Local design review, 19 September 2026.** These HTML prototypes respond to the owner's request for a complete identity and experience exploration around recording golf sessions, finding shots, keeping favourites and making social clips.

**Selected foundation:** the owner endorsed Clubhouse and requested substantial further refinement. The accepted Studio direction is to bookmark a full 10–20-minute recording and create a list of smaller source-linked shots while preserving the original. This HTML review led to the native Clubhouse/Cutroom implementation in [ADR 0014](../../context/decisions/0014-native-recording-studio-and-source-linked-shots.md); see [Current State](../../context/CURRENT_STATE.md) for verification. The files here preserve the exploration. [ADR 0013](../../context/decisions/0013-clubhouse-and-bookmarked-recording-studio.md)

The executed native design is available in the [Simulator captures](native-evidence/README.md). Open `index.html` through a local web server to revisit the original exploration. The individual concept pages also work independently with the sibling CSS, JavaScript and assets.

```sh
cd '/Users/hojaejung/Desktop/VIbe Projects/Ronde/docs/design/2026-09-19-shot-media'
python3 -m http.server 8764 --bind 127.0.0.1
```

Then open [the review board](http://127.0.0.1:8764/). There are no package, build or external network dependencies. The active review session uses this loopback-only server. Opening files directly supports the individual concepts, but the review board's cross-frame screen shortcuts require the shared local origin.

## Review the directions

| Direction | Starting point | Character |
| --- | --- | --- |
| [Clubhouse, selected](clubhouse.html) | Session, recording Studio and keepers | Warm chalk, deep green and editorial photography. Further refinement is in progress. |
| [Cutroom](cutroom.html) | Recordings and a contact sheet | Cobalt accents, precise selection and a persistent preview. Designed for lots of footage. |
| [Fieldwork](fieldwork.html) | One moment at a time | Sand, vermilion and bold condensed type. A clear Keep/Skip rhythm. |

The board switches between illustrative iPhone, expanded Duo and iPad viewport sizes without reloading the active concept. Try the Sessions, Shots and Studio shortcuts, then the interactions inside each app. Concept switching starts that direction's sample state again.

For the Clubhouse refinement, review a full source recording, add several bookmarks, adjust their before/after windows and create the shot list. Open a resulting shot to trim, favourite, choose a format and preview a labelled trace/export. Change viewport width and check that the source position, bookmarks and edits stay in place. Five seconds on either side, boundary clamping and duplicate-free repeat extraction are proposed interaction details for review.

The separate [Duo pose study](adaptive.html) shows outer-display and inner-landscape side controls, inner-portrait horizontal controls, and a partly folded media/controls layout. These are design interpretations of [Apple's guidance](https://developer.apple.com/iphone-duo/), not a native Duo build or exact hardware dimensions.

## Product proposal and boundaries

[Product direction](PRODUCT_DIRECTION.md) separates the accepted Clubhouse and recording-Studio intent from the proposed Session / Recording / Bookmark / Shot model, optional automatic suggestions and extraction defaults. A bookmark is a source-time marker; a keeper is a favourite shot. [Brief](BRIEF.md) records the request and source context. The subsequent native implementation is recorded in ADR 0014.

All sample people, place labels, counts, moment timings and imagery are fictional. The two photographic stills were made with the built-in imagegen tool; their complete prompts and provenance are in [assets/README.md](assets/README.md). Playback animates a sample playhead over a still. Import and capture add sample data. No inference, camera access, media encoding, file export, account service or social posting occurs.

Edits last in the current concept's browser memory. The prototype is not a persistence test. The later native implementation supports recordings up to 20 minutes, bookmarks and batch Shot creation; those capabilities are validated separately from these prototypes. Automatic suggestions and hands-free capture remain optional future work; manual clipping does not depend on tracking, and unresolved native tracer accuracy is unchanged.

## Historical exploration handoff

This checkpoint predates the native execution. ADR 0014 and Current State supersede its next gate and implementation boundaries.

- Started from `codex/retire-watch-ios-only` at `17cbc55`. Another task advanced the shared checkout to `main` at `d9b405c` during exploration; no checkout or Git publication was performed here.
- The new dated concept folder and narrow context entries are local, uncommitted review work. The older `docs/design/ronde-redesign-concepts/` exploration is preserved.
- Native Swift, project configuration, tracker, persistence, hosted services and release state were not changed. The pre-existing nine-line `Package.resolved` addition was preserved.
- The follow-up records the accepted design direction in ADR 0013, the product contract, compact brief and affected context. The mapped Notion page was updated and read back with the same high-level accepted direction and native limitation; see `docs/context/NOTION_MIRROR.md`. The shared Git baseline is still unchanged.
- Next gate: owner reviews the refined bookmark-to-shots workflow and proposed extraction details before a native implementation plan.

## Validation

The original exploration checks are retained below. The recording-Studio follow-up added in-app browser checks for source start/end clamping, duplicate bookmarks, adjustable windows, remove/undo, batch creation, repeat extraction without overwriting edits, generated shot duration and trim-bounded playback, source/session isolation, and recording-to-shot-to-recording navigation. Bookmarks and edits were retained through phone, expanded and tablet layout changes. This remains simulated HTML evidence.

- All six JavaScript files passed `node --check`. All five HTML pages passed local-resource and duplicate-ID checks. Stylesheet braces, context validation and whitespace checks passed.
- In-app browser review covered 393px compact, 760px expanded and 1120px tablet layouts across the concepts; all five entry pages also reported no document-level horizontal overflow at 320px.
- Clubhouse: session selection, keeper toggle, manual trace, 9:16 fit and export preview; selection and choices retained on compact-to-expanded resize.
- Cutroom: contact-sheet selection, keeping, trace, 9:16 fit, export preview, skip and restore. Fixed and retested the explicit selected-session route when collapsing from 1120px to 393px.
- Fieldwork: Keep → Skip → Undo, Studio, manual trace, square output, keyboard trim adjustment, saved edits and export preview. State retained through compact-to-tablet resize.
- Review board: direction switching, device switching, cross-frame Studio shortcuts and structure panel. Duo study: landscape-to-tabletop transition retained trace, output choice and playhead state. Other poses are design examples, not native validation.
- One unscoped browser log reported a startup `MutationObserver` error; none of this prototype's sources instantiate a MutationObserver, and no tested flow was blocked. Its origin was not established, so this is not a claim of an entirely clean browser console.

No Xcode build, native persistence check, representative-video accuracy test, physical iPad/iPhone/Duo check or hosted-service verification was performed for this HTML-only work. Full assistive-technology, Dynamic Type and touch ergonomics review remains part of a later native implementation.
