# Native concept-fidelity correction

**19 September 2026 · native correction, source delivery authorised**

Open [the native review board](index.html) for iPhone, iPad, Duo and the previous/revised Sessions comparison. These are captures of the SwiftUI application, not HTML recreations. [ADR 0016](../../../context/decisions/0016-native-concept-fidelity-correction.md) records the owner's physical-iPhone rejection and the correction.

## Source and scope

Prepared on `codex/concept-fidelity`, based on `7a6bd012484419faf3f23011cee7f4ae12b4a6b3`, in an isolated worktree. The original checkout's separate tracer work was preserved. The owner authorised commit/push/merge and requested no further testing; Git and the delivery PR record source incorporation. No physical-phone installation, TestFlight upload or new device design acceptance is claimed.

The correction removes repeated introductory headings and generic inspector cards; restores Clubhouse typography, photographic Sessions and a two-column iPhone collection; and keeps Cutroom's playback, trim timeline, editing tabs and format silhouettes together. Recording Studio keeps both bookmark window controls above its Create action at ordinary phone text sizes. Accessibility text reflows to stacked controls and scrollable format choices. Native navigation and control surfaces use Liquid Glass where supported, with readable fallbacks.

## Captures

| Screen | iPhone 17 | iPad Pro 11-inch (M5) | Duo |
| --- | --- | --- | --- |
| Sessions | [Capture](sessions-iphone.png) | [Capture](sessions-ipad.png) | [Capture](sessions-duo.png) |
| Session detail | [Capture](session-iphone.png) | [Capture](session-ipad.png) | [Capture](session-duo.png) |
| Recording and bookmark windows | [Capture](recording-iphone.png) | [Capture](recording-ipad.png) | [Capture](recording-duo.png) |
| Shot Studio, original format | [Capture](studio-iphone.png) | [Capture](studio-ipad.png) | [Capture](studio-duo.png) |
| Shot Studio, square format | [Capture](studio-square-iphone.png) | [Capture](studio-square-ipad.png) | [Capture](studio-square-duo.png) |
| Add recording | [Capture](import-iphone.png) | [Capture](import-ipad.png) | [Capture](import-duo.png) |

The populated review journey navigates through Sessions → Session → Recording → an existing source-linked Shot. Studio captures therefore include the real pushed navigation controls. The Duo files show the active display in the available Simulator pose; a second inactive display was black. These are adaptive-layout observations, not physical folding or hinge validation.

All shot imagery is fictional concept artwork, encoded into silent 16-second movies for Debug-only preview routes. See [fixture provenance](../../../../Ronde%20iOS%20AppUITests/Resources/README.md). No private media, actual swing, ball flight or detector result appears in these captures. The previous Sessions comparison uses the earlier synthetic test pattern, so it compares hierarchy and density rather than image content.

## Verification

Xcode 27.1 (27A9269), iPhone 17 and iPad on iOS 27.0 Simulator, Duo on iOS 27.1 Simulator. Result bundles are local temporary artifacts under `/tmp`, not repository fixtures.

| Check | Result | Result bundle |
| --- | --- | --- |
| Complete iPhone UI suite during correction | All seven journeys passed | `ronde-fidelity-ui.xcresult` |
| Populated review and Session/import journeys across iPhone, iPad and Duo | Both journeys passed on all three destinations | `ronde-fidelity-adaptive.xcresult` |
| Largest accessibility text, recording → bookmark → Shot → square format, including rotation/playhead retention | Passed on iPad after replacing lazy format layout | `ronde-fidelity-accessibility-v2.xcresult` |
| Final populated iPhone visual journey | Passed; source of the final phone captures | `ronde-fidelity-final-phone.xcresult` |
| Final trim, square MP4 export and native share sheet | Passed after correcting per-option accessibility identifiers | `ronde-fidelity-final-export.xcresult` |
| Final populated iPad and Duo visual journey | Passed on both destinations; source of the final adaptive captures | `ronde-fidelity-final-adaptive.xcresult` |

The final-phone bundle also contains an earlier export failure caused by a grid-level accessibility identifier overriding the child option identifiers. That defect was fixed and the dedicated final-export run passed. The largest-text run similarly exposed unreachable lazily instantiated format choices; the eager four-option layout and focused rerun resolved it. No broad unit/media rerun is claimed for this visual correction. The underlying media pipeline and persistence implementation were not changed.

The iPad text-size setting was restored after testing. Export reached the system share sheet without sending a file to a recipient. The export report retains an AVFoundation internal QoS warning, with no test failure. A final Details-menu rerun was interrupted at the owner's request (`ronde-fidelity-final-details.xcresult`); its build completed, but no additional test pass is claimed. No more app testing was started. Context-library and whitespace checks are recorded in Current State.

The owner's earlier physical-iPhone rejection remains the latest device design result. These corrected screens are the reference for continued functionality work. Repeat signed-iPhone UAT with representative footage before treating the device workflow as accepted.
