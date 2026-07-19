# Operations

## Prerequisites

- Xcode compatible with the checked-in project.
- watchOS 10+ simulator runtime.
- XcodeGen when changing `project.yml`.
- A configured development team only for signing or hardware work.

## Inspect schemes

```bash
xcodebuild -project Ronde.xcodeproj -list
```

## Regenerate the project

`project.yml` is the configuration source. Review the generated diff before keeping it.

```bash
xcodegen generate
git diff -- Ronde.xcodeproj project.yml
```

## Build

```bash
xcodebuild -project Ronde.xcodeproj -scheme 'Ronde Watch App' -destination 'generic/platform=watchOS Simulator' build
xcodebuild -project Ronde.xcodeproj -scheme 'Ronde iOS' -destination 'generic/platform=iOS Simulator' build
```

When selecting a named watch simulator, Xcode can expose paired and standalone devices with the same name. Use `-showdestinations` and an explicit `id=<SIMULATOR_ID>` when a name is ambiguous. Do not commit machine-specific simulator IDs to the canonical command.

There is currently no automated test target. Record that absence rather than reporting a test pass.

## Preview states

The active local pass supports `RONDE_PREVIEW_SCREEN` through `RondePreviewRouter.swift` in Debug builds. Treat screenshots as evidence only after confirming the exact build, destination and requested state.

## Release evidence levels

Keep these claims separate:

1. Source inspection.
2. Xcode project generation.
3. Simulator build.
4. Simulator interaction.
5. Physical watch interaction and permission behaviour.
6. Archive and signing.
7. TestFlight or App Store availability.
