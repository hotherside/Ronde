# 0012: Make Ronde an iPhone/iPad-only shot media product

**Status:** Accepted

**Date:** 19 September 2026

## Context

Ronde began as an independent Apple Watch shot counter and later added a universal iPhone/iPad reviewer. The two products no longer support one focused proposition. The accepted direction is now the media workflow: a personal shot library, honest shot tracer, non-destructive editing and related phone/tablet features.

## Decision

- Retire the Apple Watch product completely from the current repository and product contract.
- Remove the watchOS source tree, target, scheme, iOS embedding dependency, HealthKit entitlement, Action Button intent, round models, course resources and Watch-specific build settings.
- Make the universal iPhone/iPad target the whole of Ronde rather than a packaging companion.
- Keep the existing local-first library, Shot Studio, source-timed observed tracer, separately labelled manual trace and social export boundaries.
- Do not migrate Watch round history or recreate shot counting on iPhone/iPad as part of this change.
- Keep dated Watch implementation evidence in Git and explicitly historical context only. It is not an active product promise or release gate.

## Supersedes

This decision supersedes the Watch-product boundary in ADR 0002, the independent-Watch consequence in ADR 0011 and all active contract, architecture, roadmap and operations guidance for Watch shot counting.

## Consequences

- `project.yml` and the generated Xcode project contain one application target: `Ronde iOS`, plus its unit and UI test bundles.
- The app no longer requests Watch-specific HealthKit, location or workout capabilities. Existing iPhone camera, microphone, photo-library, motion and Apple sign-in capabilities remain because they support the media workflow.
- A future wearable feature would require a new product decision and target rather than reactivating the retired implementation by default.
- The next distribution attempt must verify App Store Connect accepts the new iOS-only archive for the existing app record. Prior archives containing an embedded Watch app are dated evidence, not proof for the new package.
- The removed source remains recoverable from Git history.
