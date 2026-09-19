# Native EdgeTAM runtime and diagnostics

These Swift sources implement the frozen one-point EdgeTAM pipeline:
Pillow-compatible crop preparation, Core ML components, conditioning and rolling
video memory, binary-mask centroids, adaptive crops and bounded source-time
dropouts. The same eight `EdgeTAM*.swift` files are explicitly included in the
Ronde app target by `project.yml`; the standalone runners remain tool-only.
`EdgeTAMTrackingService` and its adapter provide the optional Shot Studio
selected-point action. Default WASB automatic tracking remains unchanged.

All media, model packages, learned constants, coordinates, fixtures and outputs
must stay in an owner-controlled directory outside this repository. The runners
do not read reference labels. A supplied point and interval remain assistance.
Empty masks never produce invented coordinates or trigger crop recentring.

## Reproduction

Compile the reusable sources plus exactly one runner. Use absolute source paths
so the runners can enforce their repository privacy boundary.

```sh
xcrun swiftc -O -swift-version 6 -parse-as-library \
  -module-cache-path /tmp/ronde-native-module-cache \
  -framework CoreML -framework ImageIO -framework CoreGraphics \
  "$PWD/Tools/TracerHarness/Native/EdgeTAMTensor.swift" \
  "$PWD/Tools/TracerHarness/Native/EdgeTAMCoreMLComponents.swift" \
  "$PWD/Tools/TracerHarness/Native/EdgeTAMImagePreprocessor.swift" \
  "$PWD/Tools/TracerHarness/Native/EdgeTAMMaskObservation.swift" \
  "$PWD/Tools/TracerHarness/Native/EdgeTAMSegmentTracker.swift" \
  "$PWD/Tools/TracerHarness/Native/EdgeTAMAdaptiveTracker.swift" \
  "$PWD/Tools/TracerHarness/Native/NativeEdgeTAMAdaptiveParity.swift" \
  -o /tmp/ronde-native-adaptive

/tmp/ronde-native-adaptive \
  --config /private/review/adaptive-config.json \
  --models /private/review/model-urls.json \
  --constants /private/review/constants.json \
  --output /private/review/new-native-evidence
```

The model map has exactly five local URL strings keyed `image`, `attention`,
`point`, `noPoint` and `memory`. Mac diagnostics may explicitly compile packages;
the backend requires compiled `.mlmodelc` resources on iOS. Each component has
validated feature names, float32 shapes and owned output storage. The point head
accepts one positive Int32 label; no-point propagation uses its separate export.
Memory features retain the original predictor's bfloat16 round trip.

The adaptive runner uses the same full-source AVFoundation PNG cache and frozen
configuration as the Python comparator. It writes source PTS, source-index
mappings, canonical masks, reset-seed diagnostics, terminations and input hashes.
Reseeding never replaces a previous canonical observation. A deadline termination
is a partial interval, even when the command completes without throwing.

For the fixed-crop check, substitute `NativeEdgeTAMParity.swift` as the only
runner. `export_native_fixture.py --help` documents private fixture generation;
it exports source RGB, learned constants and preprocessing/position goldens from
the pinned upstream model. Invoke the runner with `--fixture manifest.json
--models model-urls.json --output new-external-directory`.

`EdgeTAMSourceFrameReader.swift` is the streaming AVFoundation decoder.
Its callback owns one RGB frame at a time and retains actual sample-buffer PTS.
The source interval is optional; when used, its decoder index is relative to the
reader interval, so source PTS remain the authoritative cross-run key. Decoder
validation and cache-driven model validation are separate checks, not a combined
on-phone result.

`EdgeTAMDirectVideoFrames` is the app's pull provider. Its metadata pass records
actual BGRA sample PTS and full-source frame indices without retaining RGB.
Subsequent crop-tensor requests reuse a forward reader and one RGB frame, or
open a bounded reader for reverse/random access and verify actual PTS. It writes
no frame cache. Call `close()` on completion/cancellation. One retained RGB frame
does not bound model state, decoder buffers or total process memory.

## App resources and private device test

Main-project builds require the ignored `.local-models` link to external verified
resources: five compiled `.mlmodelc` components, `edgetam-constants.json`,
`edgetam-model-identity.json` and `edgetam-license.txt`. Use the offline
[`prepare-edgetam-app-models.py`](../scripts/prepare-edgetam-app-models.py) with an
already-built diagnostic app and verified build evidence. Complete component
trees and constants are checked before staging and again by the app service;
there is no runtime download or package compilation on iOS.

The service validates a cut of at most ten seconds, an upright normalised point
and a real seed PTS within 1 ms. It uses the frozen 512-pixel crop policy,
0.20-source-second dropout bound, 32-reset cap and 240-second propagation limit.
It returns actual canonical observations and explicit empty records, retaining
absolute source indices/PTS and partial-budget status. The adapter stores source
pixels, supplied-seed/model/policy provenance and gaps in `SeededModelTrace`.
Preview and export consume independent saved segments.

`project-tracer-device-test.yml` extends the main spec with private resources in
the XCTest target only. `EdgeTAMDeviceIntegrationTests` invokes the real app
service, checks source identity, saves actual canonical evidence, exports a short
MP4 through the production renderer and verifies archive round-trip. It skips
without the external configuration or on Simulator. Keep its result bundle and
JSON/MP4 attachments private. Restore the standard project before any delivery
build; never distribute test footage. See [Operations](../../../docs/context/OPERATIONS.md#point-assisted-app-resources-and-device-test).

## Evidence and next gate

Use [the validation ledger](../../../docs/context/TRACER_VALIDATION.md) for the
current verified results and limitations. After retaining an interrupted first
run, full native Mac adaptive parity passes: 130/130 daylight masks are identical,
117/118 night masks are identical, and the one-pixel difference has minimum IoU
0.99875 and maximum centre difference 0.0234646 pixels. Canonical output contains
120/110 frames with 104 nonempty observations each; Mac tracking takes
41.737/34.936 seconds. The direct-video provider separately passes 18 RGB and
eight tensor comparisons with exact timing/index mapping.

The app unit/domain/media suite passes 127 checks with two skips on Simulator.
The source-frame selection UI check also passes separately. Signed Release
device-test build, strict signing and bundled model identities are verified, but actual
Ronde inference/export/archive on iPhone 18 Pro/iOS 27 is pending while the device
is locked. Compilation and Mac numerical parity do not establish phone latency,
memory, thermals, representative accuracy or complete flight recovery.
