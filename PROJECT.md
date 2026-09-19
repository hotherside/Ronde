# Ronde

Ronde is a local-first universal iPhone/iPad media library for private golf-shot videos, evidence-backed shot tracing and non-destructive editing/export.

## Product promise

Import or capture a recording or shot, keep it in a private searchable Sessions library, bookmark useful moments, review source-linked Shots in a focused Studio, trim them and export a social-ready file. The active automatic line uses source-timed observed ball samples only. Untracked footage stays editable and shareable; manual annotation remains explicitly labelled. Raw video, geometry and edits stay on device, with only private account and lightweight library metadata in Supabase.

## Current stage

Pre-release product hardening and tracer validation. The September 2026 scope reset removes the Apple Watch product and makes the universal iPhone/iPad app the whole of Ronde. The current app combines a Sessions library, Recording Studio and Shot Studio with non-destructive trimming, source-frame controls, fitted social export, account-scoped storage and deterministic tracker repairs. These repairs do not establish representative real-video accuracy. The previous five-video owner TestFlight result was one inaccurate trace; physical-device performance, signed Apple login and release/distribution remain separate checks. See [Current State](docs/context/CURRENT_STATE.md) for exact verification.

The owner selected Clubhouse as the design foundation, with Cutroom's focused editing vocabulary and native Liquid Glass controls. The native app implements a Recording Studio for manual recordings up to 20 minutes: Sessions contain Recordings, bookmarks create source-linked Shots, and favourites identify Keepers. The source remains intact and shared/editable shots retain their relationship to it. See [ADR 0013](docs/context/decisions/0013-clubhouse-and-bookmarked-recording-studio.md) for the historical design selection and [ADR 0014](docs/context/decisions/0014-native-recording-studio-and-source-linked-shots.md) for the implemented contract.

The native implementation is recorded at [`6fdb6a6`](https://github.com/hotherside/Ronde/commit/6fdb6a6dcd3858f0125f657aa42337c0e661926d) with source delivery through [PR #12](https://github.com/hotherside/Ronde/pull/12). Git and the PR record the current merge state. The Simulator build, media tests and native journeys passed; Current State records exact runs. Signed-device checks and distribution remain separate from source delivery.

## Canonical context

- [Product contract](docs/product-contract.md)
- [Context library](docs/context/README.md)
- [Current state](docs/context/CURRENT_STATE.md)
- [Architecture](docs/context/ARCHITECTURE.md)
- [Roadmap](docs/context/ROADMAP.md)
- [Operations](docs/context/OPERATIONS.md)
- [History](docs/context/history/TIMELINE.md)

Git is the exact committed history. Documentation records accepted intent, verified snapshots and known uncertainty.

## Repository source

- Canonical repository: [hotherside/Ronde](https://github.com/hotherside/Ronde).
- Shared baseline: committed `main`; verify the selected branch and commit before continuing.

Use this file as the compact brief for local, cloud and ChatGPT/Work discussions, with the relevant linked context pages. Any uploaded copy is a dated snapshot: identify its source commit and verify that the destination can read it. Follow the [session-completion contract](docs/context/DOCUMENTATION_CONTRACT.md#session-completion-across-tools) to carry accepted changes back into the repository.
