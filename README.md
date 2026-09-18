# Ronde

Ronde is a local-first iPhone and iPad media library for golf-shot videos, evidence-backed shot tracing, non-destructive editing and social-ready export.

Start with [PROJECT.md](PROJECT.md) for the product overview and [AGENTS.md](AGENTS.md) for repository instructions.

## Development

```bash
xcodebuild -project Ronde.xcodeproj -scheme 'Ronde iOS' -destination 'generic/platform=iOS Simulator' build
```

The full build, preview and validation workflow is in [docs/context/OPERATIONS.md](docs/context/OPERATIONS.md).
