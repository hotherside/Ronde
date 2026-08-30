# 0005: Accept a real shot before clipping or tracing

**Status:** accepted

**Date:** 23 August 2026

## Context

The first long-video implementation treated generic motion, audio peaks and body-motion bursts as review candidates. A supplied one-swing clip produced 26 visible candidates under the original generic-trajectory approach. That model made downstream clip and tracer creation too easy and could not distinguish a target golfer's real shot from a practice swing, range noise, another golfer or another ball.

The required long-session outcome is narrower. If a five-minute recording contains three real shots by the golfer being reviewed, Ronde should surface three shot moments, create three non-destructive clips around impact and run tracer work only for those three.

## Decision

- Treat audio, pose motion and generic trajectories as event proposals, never as accepted shots.
- Require two independent evidence groups for automatic acceptance: a swing and impact attributed to the target golfer, plus a stable golf-ball-specific launch attributed to that golfer and aligned with impact in source time.
- Make validated target-golfer impact time canonical for the accepted clip, playback bounds and tracer reveal. The initial proposal timestamp remains diagnostic only.
- Keep accepted shots, uncertain moments and rejected events as separate domain collections.
- Give only accepted shots a clamped impact -5/+5 clip plan and tracer eligibility.
- Keep uncertain moments recoverable in a secondary no-tracer correction queue. Do not surface rejected generic-motion, range-noise or different-golfer events in the primary workflow.
- Enforce the decision at downstream API boundaries for automatic clip export and trajectory analysis, not only in the interface.
- Fail closed when the validated detector or target-person association is unavailable. A zero-shot automatic result is preferable to false shot clips and fabricated tracers.
- Permit a deliberate person-confirmed correction as an assisted workflow, with inferred provenance; it is not automatic detector evidence.
- Keep rendered export/share absent until the accepted source range and tracer can be composed into the derivative; never label the full original recording as the finished shot clip.

## Alternatives considered

- Create a clip from every audio or pose marker: rejected because practice swings and range noise would recreate the false-candidate problem.
- Run a tracer over every proposed moment and let the user delete mistakes: rejected because tracer presence falsely implies ball evidence and burdens review.
- Promote generic `VNDetectTrajectoriesRequest` results to golf-ball evidence: rejected because the request detects motion trajectories, not object identity or ownership.
- Integrate an unvalidated public YOLO checkpoint immediately: rejected after the candidate checkpoint produced discontinuous false detections on the supplied sample and its training provenance was not strong enough for a commercial release decision.

## Consequences

- The orchestration, state separation, clip planning and tracer gates can be tested before detector weights are ready.
- Production long-session imports currently return uncertain moments rather than automatic shots because no validated golf-ball detector is installed.
- Competitive automatic segmentation remains blocked on representative labelled footage, commercially usable model provenance and held-out precision/recall validation.
- The interface now makes real-shot playback primary and keeps the correction queue secondary.
