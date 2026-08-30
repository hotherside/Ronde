# 0008: Short-shot-video MVP and perspective flight estimate

- **Status:** accepted
- **Date:** 30 August 2026
- **Supersedes:** the exposed Range Session workflow and numerical-carry prohibition in ADR 0007

## Context

The first evidence-backed reviewer could identify a short mid-air ball fragment, but its completion model only projected forward for a bounded screen-space interval. Playback and export also began the reveal at the first observed point. The result was an honest but unusable tracer stub that appeared to start in the sky, did not reach a credible landing and did not communicate an apex or any useful carry guidance.

Ronde already contains proposal, long-session segmentation and target-golfer association foundations. Exposing those unfinished workflows diluted the product without improving the core one-shot result. The MVP needs to make one short, fixed-camera shot video useful before attempting unattended slicing of a long range recording.

A monocular uncalibrated video cannot produce launch-monitor-grade carry. It can, however, fit several plausible perspective flight models to a verified source-timed ball fragment and honestly expose their spread as a rough range.

## Decision

- The iPhone/iPad MVP exposes one `Shot Video` import, limited to 60 seconds. It retains and reviews the full source range rather than creating an impact-minus-five/plus-five clip.
- Impact detection remains an internal timing input. The primary one-shot interface does not ask the golfer to acknowledge, classify or confirm the shot before review.
- Range Session segmentation, target-golfer association and Live Review foundations remain in source but are dormant and not part of the current MVP surface.
- Automatic tracer eligibility is unchanged: a confidence-gated, source-timed golf-ball track is required. Audio, body motion, generic Vision motion and default geometry cannot create a visible automatic path.
- A passing observed fragment may seed a perspective-aware ballistic presentation fit. The fit may estimate backwards from the first observation to impact and forwards through an apex to a bounded landing point.
- Estimated launch and continuation geometry use a dashed purple treatment. Detector-attributed points use a solid-purple causal trail whose endpoint is held fractionally behind the source ball position, so the stroke cannot cover or appear to lead the ball. A visible `EST. APEX` marker distinguishes a modelled image-space apex.
- The observed trail is driven by the stored source presentation timestamps, including a bounded renderer-only interpolation between observations. Estimated geometry fades in only after the observed trail completes; it does not animate ahead as though it were the detected ball.
- When several similarly plausible fits pass the gate, Ronde may show their carry spread in metres as a broad range. It must be labelled `Model carry` with `Estimate · uncalibrated` and must never be described as measured, precise or launch-monitor equivalent.
- If the observed fragment is missing, not source-timed, not rising or cannot support a bounded fit, Ronde keeps the existing fail-closed `Ball flight not tracked` state rather than drawing plausible geometry.
- Playback and export use the same stored geometry and common source cadence. Export does not rerun tracking.

## Alternatives considered

- **Keep the observed mid-air fragment only:** rejected because it is technically honest but does not deliver the consumer tracer the product promises.
- **Draw a generic launch-to-landing parabola:** rejected because it repeats the fabricated-fallback failure and would appear on unsupported footage.
- **Show one precise carry number:** rejected because monocular ambiguity is material. A rounded range better communicates uncertainty.
- **Keep Range Session as a parallel MVP workflow:** deferred until one-shot quality, representative footage accuracy and physical-iPhone performance are credible.

## Consequences

- The MVP is narrower and easier to evaluate: one video, one shot, one automatic result or an explicit failure.
- The automatic path can begin at impact and continue to a modelled landing even when the detector sees only a mid-air fragment, while preserving the observed-versus-estimated distinction.
- Carry is useful directional guidance, not a measurement. Known-ground-truth calibration remains necessary before Ronde may claim precise distance or apex height.
- Existing long-session and live code requires continued tests while dormant, or later removal if the product permanently abandons those paths.
- Representative positive and negative footage, output-video inspection and physical-device performance remain release gates.
