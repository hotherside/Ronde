# Current State

**Reviewed:** 7 September 2026

**Context maintenance:** 12 September 2026, documentation-only review from committed `main` at `886478e`. The product and external verification dates below are unchanged. Inspect the current checkout/ref and the existing next gates before continuing; follow the [session-completion contract](DOCUMENTATION_CONTRACT.md#session-completion-across-tools).

**Delivery scope:** library and shot-studio redesign, local archive/import safety and deterministic tracker repairs. Git is authoritative for the current branch, commit and merge state.

## Stage

Ronde remains pre-release. The Watch is the independent offline shot counter. iPhone/iPad now centre on a searchable Shot library and a single media studio for playback, frame stepping, trim, trace and social export. Settings replace Profile. The active automatic overlay uses only accepted source-timed observed samples; predicted flight, landing and numerical carry are absent from the studio. Manual annotations remain separate and labelled.

The prior signed-iPhone TestFlight check produced only one automatic trace across five owner-selected videos, and that line was visually inaccurate. This remains unresolved accuracy evidence. The new source-cadence, track-lineage, loss/reacquisition and apex repairs address reproducible component failures; they do not validate the model on representative golf footage.

## Capability status

| Capability | Current source behaviour | Evidence boundary |
| --- | --- | --- |
| Watch | Independent counting, undo, holes, local history and optional workout | No Watch behaviour changed in this redesign; hardware validation remains open |
| Library | One media grid, search/favourites, settings, local details and direct import-to-editor routing | Simulator and synthetic tests; signed account flow remains a separate gate |
| Studio | Fitted video, pause/resume, scrubbing, real source-frame timing, thumbnail trim and saved edits | Original source remains unchanged |
| Trace | Automatic observed samples only; removable, separately authored manual path | No claimed accuracy gain without labelled source comparison |
| Export | H.264 MP4, selected source range, original/9:16/1:1/16:9 fit canvas, trace choice and source audio | No implicit crop; physical-iPhone speed, HDR/codec and sharing matrix remain open |
| Local storage | Typed read failures, blocked corrupt archive writes, surfaced/retryable saves, relative owned-media paths | Account generation checks protect asynchronous imports; interrupted analysis can retry |
| Account metadata | Existing Supabase profile and lightweight library sync | Hosted schema/provider verification dates to 30 August; remote restore/deletion outbox and cold offline auth are not completed |
| Range/Live | Dormant foundations | No long-session capture or automatic hands-free loop is promised |

## Verification

- The complete iPhone 17 Pro iOS 26.0 scheme passed: 115 checks scheduled, 112 passed, three optional external-media checks skipped, zero failures. This includes four native UI journeys and four actual encoder integration tests.
- Encoder tests checked fractional trim duration, H.264/AAC output, original-file preservation, observed-line pixel alignment, omitted extrapolation, preferred rotation and cancellation. The separate production encoder harness also exercised all four output formats.
- Native UI tests passed library-to-studio navigation, Details Cancel, manual Cancel, pause/resume, fine trimming, square export and native share-sheet presentation. No social recipient was selected or file posted.
- Generic Watch Simulator build, context validation and whitespace checks passed. iPhone SE iOS 17.5 and iPad Pro iOS 26.0 fixture layouts were inspected; the largest SE text size exposed and then verified a timestamp/transport reflow correction.
- Source compilation, synthetic media and Simulator results do not establish representative ball-tracking accuracy, physical-device reliability or App Store delivery.

## Remaining release gates

- Label the exact five owner clips, with visible ball centres, impact and loss intervals. Add representative held-out positives and distractor negatives. Report acquisition recall, false traces, point error, visible-track coverage and latency separately.
- Review actual rendered line alignment and trimmed social exports frame by frame on a signed iPhone, including portrait rotation, slow motion/VFR, silent sources and audio.
- Complete first/repeat Apple login, cold offline launch, two-account archive isolation and cloud metadata failure/reconciliation checks.
- Verify Watch start/recovery/end, Action Button, permission denial and terminated-round recovery on hardware. The audit's pending-start race remains follow-up work.
- Verify signing, TestFlight compliance/internal access and distribution directly. This source merge is not a TestFlight upload.

See [ADR 0011](decisions/0011-library-and-shot-studio.md), [Roadmap](ROADMAP.md) and [review findings](reviews/2026-09-07-app-review.md).
