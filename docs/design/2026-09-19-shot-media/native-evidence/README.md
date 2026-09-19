# Native Clubhouse and Cutroom implementation

Captured on 19 September 2026 during implementation on `codex/clubhouse-native-studio`, based on `d9b405c`. The captured native implementation is recorded at `6fdb6a6` in [PR #12](https://github.com/hotherside/Ronde/pull/12). These are native SwiftUI Simulator screenshots, not HTML concepts. The media is the repository's generated test pattern; there is no private golf footage or tracking-accuracy evidence here.

The iPhone captures come from two passing native journeys in `ronde-clubhouse-screenshots.xcresult` on the dedicated iPhone 17 iOS 27.0 Simulator. The iPad capture comes from the passing adaptive run on iPad Pro 11-inch (M5), iOS 27.0, at the largest accessibility text size. Result bundles remain temporary local artifacts. [Current State](../../../context/CURRENT_STATE.md#verification) records the complete validation and remaining hardware gates.

| Screen | Capture |
| --- | --- |
| Sessions, including native tab navigation | [iPhone](sessions-iphone.png) |
| Source playback and bookmark action | [iPhone](recording-studio-iphone.png) |
| Trim/Trace/Format inspector with all four canvases | [iPhone](shot-studio-formats-iphone.png) |
| Photos, Files and native camera entry | [iPhone](add-recording-iphone.png) |
| Wide Studio with accessibility text reflow | [iPad](shot-studio-ipad-accessibility.png) |

The Recording Studio and format captures show different scroll positions in the same tested recording → bookmark → Shot journey. The six-test iPhone suite also passed cancellation, playback, trimming, square encoding and native share-sheet presentation. Duo interaction checks passed on the matching iOS 27.1 runtime; no physical fold or hinge behaviour is claimed.
