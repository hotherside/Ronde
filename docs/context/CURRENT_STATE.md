# Current State

**Reviewed:** 19 September 2026

**Design correction:** the owner rejected the PR #12 native design after physical-iPhone UAT on 19 September: it diverged from the Clubhouse/Cutroom concepts and had unnecessary headings, subheadings and weak typography. The correction was prepared on `codex/concept-fidelity` from `7a6bd01`, isolated from separate tracer work. After the completed checks below, the owner explicitly authorised commit/push/merge and requested no further testing. [ADR 0016](decisions/0016-native-concept-fidelity-correction.md) records the correction. Git and the delivery PR record incorporation into `main`; a new signed-device design pass remains open.

**Correction source:** implementation and native captures are committed at [`510fd36`](https://github.com/hotherside/Ronde/commit/510fd3602977576a98aa2335b05135637ac1b549) and delivered through [PR #13](https://github.com/hotherside/Ronde/pull/13). The follow-up delivery commit changes documentation only. Git and the PR record the verified merge state.

**Source delivery:** the Clubhouse/Cutroom native implementation, reviewed concepts and synthetic native captures are recorded at [`6fdb6a6`](https://github.com/hotherside/Ronde/commit/6fdb6a6dcd3858f0125f657aa42337c0e661926d), prepared on `codex/clubhouse-native-studio` from `d9b405c` and delivered through [PR #12](https://github.com/hotherside/Ronde/pull/12). Git and the PR record the current merge state; committed `main` remains the shared baseline. The Apple Watch product, source target and build relationship are removed. The implementation passed the Simulator checks below; signed-device and external-service evidence remain separate. Follow the [session-completion contract](DOCUMENTATION_CONTRACT.md#session-completion-across-tools).

**Delivery scope:** iPhone/iPad-only product reset, Sessions library, Recording Studio, source-linked Shots, Shot Studio, local archive/import safety and deterministic tracker repairs. Git is authoritative for the current branch, commit and merge state.

## Stage

Ronde remains pre-release and is now exclusively a universal iPhone/iPad product. It centres on a searchable Sessions library with Recording Studio for long manual sources and Shot Studio for playback, frame stepping, trim, trace and social export. The Apple Watch shot counter and its round/workout features have been retired. The active automatic overlay uses only accepted source-timed observed samples; predicted flight, landing and numerical carry are absent from the studio. Manual annotations remain separate and labelled.

The prior signed-iPhone TestFlight check produced only one automatic trace across five owner-selected videos, and that line was visually inaccurate. This remains unresolved accuracy evidence. The new source-cadence, track-lineage, loss/reacquisition and apex repairs address reproducible component failures; they do not validate the model on representative golf footage. The current Recording Studio remains a manual source-review workflow and makes no new tracer-accuracy claim.

## Capability status

**Implemented direction, 19 September:** after reviewing the [local HTML concepts](../design/2026-09-19-shot-media/README.md), the owner selected Clubhouse as the foundation, with Cutroom's editing vocabulary and native Liquid Glass controls. The local native slice implements Sessions → Recordings → Bookmarks → source-linked Shots, with favourites identifying Keepers. Manual recordings accept up to 20 minutes from Photos, Files or the native camera. Each bookmark defaults to ±5 seconds, can be adjusted in 5-second increments from 0 to 60 seconds per side, clamps to the source and can be batch-extracted once while preserving existing Shot edits. [ADR 0013](decisions/0013-clubhouse-and-bookmarked-recording-studio.md) remains the historical design selection; [ADR 0014](decisions/0014-native-recording-studio-and-source-linked-shots.md) records the implemented local contract.

Recording Studio plays the full source and generates a sparse thumbnail strip, capped at 12 frames. A derived Shot's frame index and thumbnails are restricted to its source clip plus five seconds on either side, retaining absolute source timestamps. Automatic moment suggestions and automatic analysis of long-source derived Shots remain deferred; those Shots start untraced and support manual annotation. Manual recording review does not require a ball track.

| Capability | Current source behaviour | Evidence boundary |
| --- | --- | --- |
| Library | Session grouping with Recordings, source-linked Shots, search/favourites, settings, local details and direct Studio routing | Session navigation and add-recording context passed on iPhone, iPad and Duo Simulators; signed account flow remains a separate gate |
| Recording Studio | Up to 20-minute manual recordings, full-source playback, sparse thumbnails, bookmarks, ±5-second defaults, 5-second adjustments from 0–60 seconds, duplicate-safe batch Shot creation | Actual sparse 20-minute media accepted and preserved in tests; bookmark/Shot UI passed; representative long-source performance and hardware capture remain separate gates |
| Shot Studio | Fitted video, pause/resume, scrubbing, source-frame timing, Trim/Trace/Format tabs, actual format tiles, thumbnail trim and saved edits | Source-linked Shot opening and format selection passed on iPhone, iPad and Duo; all six iPhone UI journeys passed |
| Trace | Automatic observed samples only; removable, separately authored manual path | No claimed accuracy gain without labelled source comparison |
| Export | H.264 MP4, selected source range, original/9:16/1:1/16:9 fit canvas, trace choice and source audio | No implicit crop; physical-iPhone speed, HDR/codec and sharing matrix remain open |
| Local storage | Typed read failures, blocked corrupt archive writes, surfaced/retryable saves, relative owned-media paths | Account generation checks protect asynchronous imports; interrupted analysis can retry |
| Account metadata | Existing Supabase profile and lightweight library sync | Hosted schema/provider verification dates to 30 August; remote restore/deletion outbox and cold offline auth are not completed |
| Range/Live | Dormant automatic-capture foundations; manual camera recording is available through Add recording | No automatic hands-free capture loop is promised |

## Verification

### Concept-fidelity correction

The `codex/concept-fidelity` correction from `7a6bd01` responds to the owner's physical-iPhone rejection. The [native review board](../design/2026-09-19-shot-media/native-fidelity/index.html) and [validation record](../design/2026-09-19-shot-media/native-fidelity/README.md) contain the final screenshots and fixture provenance. All evidence in this subsection is Simulator evidence. Source delivery does not update the owner's phone installation.

- All seven iPhone UI journeys passed during correction (`ronde-fidelity-ui.xcresult`). The populated review and Session/import journeys also passed across iPhone 17, iPad Pro 11-inch (M5) and Duo (`ronde-fidelity-adaptive.xcresult`).
- Focused final runs passed for the real pushed Sessions → Recording → Shot flow on iPhone (`ronde-fidelity-final-phone.xcresult`) and on iPad and Duo (`ronde-fidelity-final-adaptive.xcresult`). Captures show the media, transport, trim timeline and four format choices together at ordinary text sizes. Duo evidence is for the available Simulator pose, not physical fold/hinge behaviour.
- Largest-text iPad recording/bookmark/Shot/format selection, including rotation and retained playhead, passed after fixing off-screen lazy format choices (`ronde-fidelity-accessibility-v2.xcresult`). The text setting was restored afterwards.
- The final square MP4 export/share-sheet journey passed (`ronde-fidelity-final-export.xcresult`). This supersedes the export failure in the final-phone bundle caused by a grid-level identifier overriding the child format identifiers. No recipient was selected or media posted. The report contains an AVFoundation internal QoS warning but no failure.
- Built with Xcode 27.1 (27A9269); iPhone/iPad used iOS 27.0 and Duo iOS 27.1. Context-library and whitespace checks passed. The unchanged unit/media pipeline was not rerun for this visual correction. A final Details-menu rerun was stopped at the owner's instruction (`ronde-fidelity-final-details.xcresult`, interrupted); its build completed, but no additional test pass is claimed. No more app testing was started. Signed-device UAT remains a separate gate.

### Earlier merged implementation

The following results cover the 19 September native implementation recorded at `6fdb6a6`; subsequent delivery updates change documentation only. Xcode 27.1 (27A9269) generated/built the universal iOS 17+ app and its two test bundles. No Watch target or embedding relationship remains.

| Check | Destination | Result |
| --- | --- | --- |
| Unit, domain and media integration suite | iPhone 17, iOS 27.0 Simulator | 119 passed, 3 optional external-media checks skipped, 0 failures; `ronde-clubhouse-units-final.xcresult` |
| Complete native UI suite | Dedicated Ronde iPhone 17, iOS 27.0 Simulator | 6 passed, 0 failures; `ronde-clubhouse-ui-isolated.xcresult` |
| Session navigation and recording → bookmark → Shot → format journeys | iPad Pro 11-inch (M5), iOS 27.0 Simulator, largest accessibility text | Both passed, including rotation and retained playhead; `ronde-clubhouse-adaptive.xcresult` |
| Same two adaptive journeys | iPhone Duo, iOS 27.1 Simulator | Both passed on the matching installed runtime; no physical fold/hinge claim; same adaptive result bundle |

- Media tests wrote an actual sparse 1,200-second asset, imported and copied it into the archive, created an absolute 595–605-second Shot around a 600-second bookmark, reloaded shared source references and checked original bytes. A 1,201-second source was rejected. This verifies duration/range/storage behaviour, not sustained 20-minute recording performance.
- Domain/archive tests cover old archive decoding, source-boundary clamping, duplicate extraction preserving edits, failed-save rollback and linked-source deletion protection. Frame-reader tests exercise bounded source timestamp ranges.
- Encoder tests checked fractional trim duration, H.264/AAC output, original-file preservation, observed-line pixel alignment, omitted extrapolation, preferred rotation and cancellation. UI tests exercised Details Cancel, manual-trace Cancel, pause/resume, fine trimming, format selection, square export and native share-sheet presentation. No social recipient was selected or file posted.
- Native visual review corrected primary glass-button contrast, large-text transport overlap, stacked controls and filmstrip width. The iPad's accessibility text setting was restored after testing. [Saved native captures](../design/2026-09-19-shot-media/native-evidence/README.md) use synthetic media and are layout evidence, not golf-tracking evidence. The two screenshot journeys were rerun successfully after adding a fallback for single-display capture.
- Result bundles are local temporary artifacts under `/tmp`, not portable repository fixtures. An earlier combined report stalled at finalisation and a shared-device UI run suffered focus interference from another task; both were superseded by the clean separate results above. Runtime AVFoundation QoS warnings remain diagnostic findings, with no test failures.
- Context validation and whitespace checks passed. Source compilation, synthetic media and Simulator results do not establish representative ball-tracking accuracy, physical-device reliability or App Store delivery. Earlier release and iOS 17 visual checks remain dated evidence in the changelog.

## Remaining release gates

- Label the exact five owner clips, with visible ball centres, impact and loss intervals. Add representative held-out positives and distractor negatives. Report acquisition recall, false traces, point error, visible-track coverage and latency separately.
- Review actual rendered line alignment and trimmed social exports frame by frame on a signed iPhone, including portrait rotation, slow motion/VFR, silent sources and audio.
- Complete first/repeat Apple login, cold offline launch, two-account archive isolation and cloud metadata failure/reconciliation checks.
- Verify Photos/Files permissions and actual camera capture on signed hardware, including representative 20-minute recordings, interruption recovery, memory/thermal behaviour and repeated editing/export. The Simulator source-range/archive checks do not close this gate.
- Verify signing, TestFlight compliance/internal access and distribution directly. Merged source is not a TestFlight upload.

See [ADR 0014](decisions/0014-native-recording-studio-and-source-linked-shots.md), [ADR 0013](decisions/0013-clubhouse-and-bookmarked-recording-studio.md), [ADR 0012](decisions/0012-ios-ipad-only-product.md), [ADR 0011](decisions/0011-library-and-shot-studio.md), [Roadmap](ROADMAP.md) and [review findings](reviews/2026-09-07-app-review.md).
