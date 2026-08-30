# Ronde

Ronde is an independent Apple Watch golf companion for counting shots and reviewing a round, with a local-first universal iPhone/iPad Shot Reviewer for private range-video review.

## Product promise

Start a round quickly, log one shot per physical action, see the current hole and score clearly, and retain a trustworthy local record after finishing. On iPhone and iPad, sign in with Apple, import one fixed-camera shot video up to 60 seconds and keep it in an account-scoped local library. Home, Library and Profile expose real recent activity, favourites, trace availability and rough supported carry ranges; optional place, club and notes remain editable on each review. When Ronde establishes a real ball track, it draws a causal solid-purple trail behind the detector-attributed ball positions and may fit distinctly dashed estimated geometry back towards impact and forwards through a marked apex to landing. When several plausible fits pass the gate, it may show their rounded carry spread in metres as `Model carry` with `Estimate · uncalibrated`; this is not measured distance. When the footage cannot support the fit, Ronde says `Ball flight not tracked` and offers a labelled manual trace instead. The reviewed geometry can be rendered into a local shareable video without rerunning detection. Raw media and analysis remain on device; Supabase stores only private account and lightweight library metadata. Every uploaded frame rate is accepted and sampled by presentation timestamp. Long-session slicing and hands-free review remain later work.

## Current stage

Ronde is in pre-release product hardening and reviewer validation. The current working tree contains the reliability, Action Button, workout-recovery, persistence and visual pass for Watch, plus a redesigned local-first iPhone/iPad app with Apple-only sign-in, an account-scoped library, real activity summaries, editable review details, timestamp-based tracking, perspective-aware completion, manual rescue and export. The private Supabase metadata schema is live and its Apple provider is enabled for native client ID `com.ronde`; the Apple Developer capability and signed-device login still require direct verification. One owner-supplied rendered output has been inspected; a representative footage matrix, representative output review, physical-device performance and distribution status still require direct verification. See [Current State](docs/context/CURRENT_STATE.md) before making release claims.

## Canonical context

- [Product contract](docs/product-contract.md)
- [Context library](docs/context/README.md)
- [Current state](docs/context/CURRENT_STATE.md)
- [Architecture](docs/context/ARCHITECTURE.md)
- [Roadmap](docs/context/ROADMAP.md)
- [Operations](docs/context/OPERATIONS.md)
- [History](docs/context/history/TIMELINE.md)

Git is the exact committed history. Documentation records accepted intent, verified snapshots and known uncertainty.
