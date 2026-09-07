# Ronde

Ronde is an independent Apple Watch golf companion for counting shots and reviewing a round, with a local-first universal iPhone/iPad Shot Reviewer for private range-video review.

## Product promise

Start a round quickly, log one shot per physical action and retain a trustworthy local record. On iPhone and iPad, import a shot video into a private library, review it in a focused studio, trim it and export a social-ready file. The active automatic line uses source-timed observed ball samples only. Untracked footage stays editable and shareable; manual annotation remains explicitly labelled. Raw video, geometry and edits stay on device, with only private account and lightweight library metadata in Supabase.

## Current stage

Pre-release product hardening and reviewer validation. The September 2026 redesign replaces Home/Library/Profile dashboards with one library and media studio. It includes non-destructive trimming, source-frame controls, fitted social export, safer account-scoped storage and deterministic tracker repairs. These repairs do not establish representative real-video accuracy. The previous five-video owner TestFlight result was one inaccurate trace; physical-device performance, signed Apple login and the release/distribution gates remain separate checks. See [Current State](docs/context/CURRENT_STATE.md) for exact verification.

## Canonical context

- [Product contract](docs/product-contract.md)
- [Context library](docs/context/README.md)
- [Current state](docs/context/CURRENT_STATE.md)
- [Architecture](docs/context/ARCHITECTURE.md)
- [Roadmap](docs/context/ROADMAP.md)
- [Operations](docs/context/OPERATIONS.md)
- [History](docs/context/history/TIMELINE.md)

Git is the exact committed history. Documentation records accepted intent, verified snapshots and known uncertainty.
