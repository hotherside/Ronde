# Ronde

Ronde is a watchOS-first, offline-first golf shot counter built with SwiftUI, SwiftData, App Intents, HealthKit, Core Location and Core Motion.

Start with [PROJECT.md](PROJECT.md) for the product overview and [AGENTS.md](AGENTS.md) for repository instructions.

## Development

```bash
xcodebuild -project Ronde.xcodeproj -scheme 'Ronde Watch App' -destination 'generic/platform=watchOS Simulator' build
```

The full build, preview and validation workflow is in [docs/context/OPERATIONS.md](docs/context/OPERATIONS.md).
