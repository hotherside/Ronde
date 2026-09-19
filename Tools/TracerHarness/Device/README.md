# Standalone device tracker probe

`TrackerDiagnosticApp.swift` is a small, separate iOS application for measuring the
current local tracker on a supplied device. It is not part of the Ronde product and
does not change the product's persistence, analysis, or UI paths. The app bundle ID is
`com.ronde.trackerdiagnostic`.

The private staging project supplies the exact current tracker, selector, and review
model sources from the checkout, together with private media and the compiled model.
The staging project and its resources must live outside this repository, for example
at `<private-device-build-directory>`.

Both standalone diagnostic entry points use `UIApplicationDelegate.configurationForConnecting`
and a dedicated `UIWindowSceneDelegate`; they never construct a window from
`UIScreen.main.bounds`. The private target must opt into scene sessions in its generated
Info.plist. No delegate class name is required in the plist because the app delegate supplies it
programmatically. The required manifest is:

```xml
<key>UIApplicationSceneManifest</key>
<dict>
  <key>UIApplicationSupportsMultipleScenes</key>
  <false/>
  <key>UISceneConfigurations</key>
  <dict>
    <key>UIWindowSceneSessionRoleApplication</key>
    <array>
      <dict>
        <key>UISceneConfigurationName</key>
        <string>Default Configuration</string>
      </dict>
    </array>
  </dict>
</dict>
```

Without this manifest, iOS 27 terminates the diagnostic target with
`UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption` before the probe can provide
model or memory evidence.

The bundled `Config/diagnostic-config.json` is generated privately. It contains opaque
clip IDs, resource names, source PTS impact times, media SHA-256 values, expected upright
dimensions, the source revision, source file hashes, and hashes for the source ML package
and its weight file. It must never contain private media, frame coordinates, or account
data. A representative shape is:

```json
{
  "schemaVersion": 1,
  "sourceRevision": "<commit-or-working-tree-revision>",
  "sourceHashes": {"<repo-relative-file>": "sha256:<digest>"},
  "sourceModelBundleSHA256": "sha256:<source-mlpackage-digest>",
  "sourceModelWeightSHA256": "sha256:<weight-file-digest>",
  "sourceModelHashScope": "source-mlpackage-directory-and-weight-file",
  "expectedCompiledModelSHA256": "sha256:<compiled-model-manifest-digest>",
  "clips": [{
    "clipID": "<opaque-clip-id>",
    "resource": "<bundled-resource-name-without-.mov>",
    "impactSourcePTS": 0.0,
    "sourceHash": "sha256:<media-digest>",
    "expectedUprightWidth": 0,
    "expectedUprightHeight": 0
  }]
}
```

At launch, the probe records a run UUID, `uname` hardware identifier, OS version,
bundle identifier, source model provenance, the expected compiled model manifest digest,
and the actual compiled model hashes. The compiled model digest is a deterministic sorted
manifest of relative path, tab, per-file SHA-256, and newline. Before each clip it hashes
the original bundled media and checks the upright dimensions after the track's preferred
transform. A clip is not analysed if either identity check fails. The impact value is an
absolute source presentation timestamp, not a frame index or a clip-relative export time.
Each result reports total wall time, preflight time, and analysis time separately.

Memory sampling begins before tracker model analysis and runs in a cancellation-safe
detached task at 20 ms intervals. `sampledPeakResidentBytes` and
`sampledPeakFootprintBytes` are sampled peaks for that clip and are explicitly labelled
as such. `processLifetimePeakResidentBytes` comes from Darwin's
`mach_task_basic_info.resident_size_max`; it is the lifetime peak for the process and
must not be read as a per-clip peak. Thermal state is sampled alongside memory and the
maximum state is retained for each clip. The aggregate instrumentation callback is used
for counters only; the raw diagnostics callback is nil, so candidate/window arrays are
not retained. Final selected source-time positions are saved privately for accuracy scoring.

Evidence is written to the app's Documents directory using the run UUID. The initial
running record is written before analysis, and the record is atomically updated after
each clip, so an interrupted run retains completed clips. Idle-timer suppression is
enabled only for the probe and restored on completion. Persistence errors are surfaced in
the status view and stop the run; the previous atomically completed file is retained when
available. This probe has no accuracy claim;
device results remain pending until separately reviewed against source-timed reference
labels.

## Private build

From the private staging directory, generate the Xcode project and build for a generic
iOS device. The derived data path is also private:

```sh
PRIVATE_DEVICE_BUILD_DIR="${PRIVATE_DEVICE_BUILD_DIR:?set an external staging directory}"
DEVELOPMENT_TEAM_ID="${DEVELOPMENT_TEAM_ID:?set the signing team identifier}"
cd "$PRIVATE_DEVICE_BUILD_DIR"
xcodegen generate
xcodebuild \
  -project RondeTrackerDiagnostic.xcodeproj \
  -scheme RondeTrackerDiagnostic \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$PRIVATE_DEVICE_BUILD_DIR/DerivedData" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM_ID" \
  build
```

Building and signing the standalone bundle does not install or launch it. Any device
run requires a separate explicit review, a connected test device, and private media and
configuration supplied outside Git.
