# Ronde Timeline

## 3 May 2026: initial watch product build

- Established the standalone watchOS product and minimal iOS packaging companion.
- Built setup, scoring, hole transition, summary and local history flows.
- Added SwiftData models, HealthKit workout support, location, pedometer and App Intents foundations.
- Iterated navigation, shared components and watch-specific visual hierarchy across 41 commits.

## 19 July 2026: watch hardening release candidate and context consolidation

- Prepared persistence recovery, workout recovery, safer Action Button behaviour, preview routing and a wide visual pass for publication.
- Established the repository-owned cross-tool context library.
- Kept real-device behaviour, automated tests and distribution as explicit follow-up evidence gates.

## August to early September 2026: universal shot media app

- Expanded the iOS packaging target into a universal iPhone/iPad Shot library and studio.
- Added local-first media, evidence-gated automatic tracing, manual annotation, non-destructive trimming and fitted social export.
- Kept representative footage, signed-device performance and distribution as explicit evidence gates.

## 19 September 2026: iPhone/iPad-only reset

- Retired the Apple Watch product and removed its source, target, scheme, entitlements and iOS embedding relationship.
- Made the universal shot media library, tracer and editor the whole of Ronde under ADR 0012.
- Retained earlier Watch details here, in the archived state and in Git only as dated history.

The complete committed sequence is in [commit-ledger.md](commit-ledger.md).
