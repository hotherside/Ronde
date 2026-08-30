# 0010: Immersive review and full-screen manual trace editing

**Status:** Accepted

**Date:** 30 August 2026

## Context

The first native redesign retained too much of the earlier reviewer workspace. Individual footage sat inside several nested containers, in-video measurement cards competed with navigation, and manual tracer handles were edited inside the same constrained card. The result did not match the accepted Caddie prototype hierarchy or provide enough precision for placing a ball path on iPhone and iPad.

Manual rescue also needs an explicit transaction boundary. A golfer must be able to explore adjustments without silently replacing stored geometry, while automatic observed evidence remains immutable and separately attributable.

## Decision

- Individual media review is an immersive, video-first route that hides the app tab bar and standard navigation bar. A small system-glass layer provides Back, Favourite and Edit details actions.
- Evidence metrics, provenance and sharing live once in the review panel below the video. Compact apex and landing markers may remain on the video, but duplicate carry and provenance cards are suppressed on this route.
- Manual tracing is presented full-screen. Impact, Apex and Landing are adjusted directly over the aspect-fitted source video rather than through a nested editor card.
- The editor owns a local draft with point selection, source-frame stepping, Undo and Reset. Cancel discards that draft. Save alone writes an `AssistedTracerPath` through `ReviewerStore`.
- Saved manual geometry remains labelled `Manual trace` and user-authored. It does not mutate or relabel automatic observed evidence, and it cannot create a measured-distance claim.
- Liquid Glass is reserved for navigation and transient editing controls on iOS 26. Earlier supported systems receive a restrained native-material fallback. Content cards remain solid and readable.

## Alternatives considered

- Keep inline editing within the review card: rejected because the video becomes too small for precise placement and the hierarchy remains container inside container.
- Persist every drag immediately: rejected because Cancel would be dishonest and accidental movement would destroy the prior manual edit.
- Hide all automatic provenance while reviewing: rejected because the user still needs clear evidence and estimate labelling; it belongs below the video rather than duplicated over it.
- Build a custom glass renderer: rejected because system Liquid Glass provides the correct adaptive material, interaction and accessibility behaviour on iOS 26.

## Consequences

- Review has a clearer boundary between watching, understanding evidence and editing the path.
- Manual edits need a full-screen presentation path and deterministic preview state on both iPhone and iPad.
- Future manual tools must preserve draft-safe Cancel/Save semantics and user-authored provenance.
- Simulator layout evidence does not prove signed-device gestures, video-frame accuracy or physical-iPad ergonomics; those remain separate validation gates.
