# Ronde

Ronde is an independent Apple Watch golf companion for counting shots and reviewing a round, with a universal iPhone/iPad Shot Reviewer for local range-video review.

## Product promise

Start a round quickly, log one shot per physical action, see the current hole and score clearly, and retain a trustworthy local record after finishing. On iPhone and iPad, import fixed-camera range footage and open a single swing directly into source-time-synchronised playback. When Ronde establishes a real ball launch, it draws the observed segment as a solid line and a clearly labelled estimated continuation as a dashed line; when it cannot, it says `Ball flight not tracked` and offers a labelled manual trace instead. The reviewed geometry can be rendered into a local shareable video without rerunning detection. Range imports may create automatic clips only after the user confirms a fixed, single-golfer setup and the target impact and ball launch agree; practice swings, generic motion, background sounds and another golfer's ball stay out of the shot rail. Every uploaded frame rate is accepted and sampled by presentation timestamp. Numerical distance remains unavailable without calibration and ground truth.

## Current stage

Ronde is in pre-release product hardening and reviewer validation. The current release candidate contains the reliability, Action Button, workout-recovery, persistence and visual pass for Watch, plus a functioning local iPhone/iPad tracer workflow with timestamp-based tracking, evidence-anchored completion, manual rescue, export and a refined adaptive review surface. A representative footage matrix, physical-device performance, complete hands-free rolling capture and distribution status still require direct verification. See [Current State](docs/context/CURRENT_STATE.md) before making release claims.

## Canonical context

- [Product contract](docs/product-contract.md)
- [Context library](docs/context/README.md)
- [Current state](docs/context/CURRENT_STATE.md)
- [Architecture](docs/context/ARCHITECTURE.md)
- [Roadmap](docs/context/ROADMAP.md)
- [Operations](docs/context/OPERATIONS.md)
- [History](docs/context/history/TIMELINE.md)

Git is the exact committed history. Documentation records accepted intent, verified snapshots and known uncertainty.
