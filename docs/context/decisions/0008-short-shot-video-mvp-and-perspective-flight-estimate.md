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
- Around impact, the tracker may independently identify the stationary ball from source frames as a compact bright object that disappears into the accepted launch corridor. The launch anchor is optional and accepted only when one candidate is uniquely defensible; ambiguous frame-difference evidence must not move the starting point or create eligibility by itself.
- A passing observed fragment may seed a perspective-aware ballistic presentation fit. The fit may estimate backwards from the first observation to impact and forwards through an apex to a bounded landing point.
- Automatic launch, observation and continuation geometry use one smoothly tapered solid-purple broadcast ribbon. Estimated ranges use subtly lower opacity while detector-attributed geometry remains fully opaque and causally behind the source ball. The former dashed-segment treatment is superseded because it made one flight read as separate drawings. A visible `EST. APEX` marker distinguishes a modelled image-space apex.
- Playback and export use one impact-to-landing timeline and one renderer-smoothed cumulative path. Estimated launch reveals from the observed source-frame anchor, when available, to the first mid-air observation; the observed range follows stored source presentation timestamps with a sampling-derived causal lag capped at 50 ms, and estimated continuation starts only after the observed endpoint is reached. The same lag remains attached through the estimated apex and continuation. Provenance changes opacity and labels, not geometry or reveal order. The estimated apex appears when the chronological reveal reaches it; `EST. LANDING` and model carry remain hidden until landing.
- If the source ends before the modelled landing, the original model timing remains unchanged through apex and only post-apex descent may be compressed. A completed-path hold is limited to 120 ms. If the source cannot contain the apex plus causal lag, the timeline may show only the causal ascent prefix and must withhold landing and carry. This supersedes uniform whole-continuation compression; detector timestamps, fitted geometry and modelled carry remain unchanged.
- The detector-to-model join residual decays as `(1 - progress)²` and reaches zero at landing. Lateral continuation is capped from the final observation using the robust observed displacement, retains an established observed direction and blends the correction with smoothstep. A displayable landing must remain below the fitted horizon, above the launch point and inside the safe frame.
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
- Reduced Motion reveals the complete styled path at impact without progressive movement. It does not alter provenance or expose geometry before impact.
- Carry is useful directional guidance, not a measurement. Known-ground-truth calibration remains necessary before Ronde may claim precise distance or apex height.
- Existing long-session and live code requires continued tests while dormant, or later removal if the product permanently abandons those paths.
- Representative positive and negative footage, output-video inspection and physical-device performance remain release gates.
