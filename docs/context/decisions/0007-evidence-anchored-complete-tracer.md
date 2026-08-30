# 0007: Evidence-anchored complete tracers

- **Status:** accepted
- **Date:** 29 August 2026
- **Supersedes:** the observed-only rendering restriction in ADR 0006

## Context

ADR 0006 correctly removed a fixed tracer that appeared plausible but was unrelated to the uploaded ball. Its stronger ball-identity gate must remain. The observed-only rendering rule, however, limits a successful detector result to the short period in which a tiny ball remains resolvable. That produces a launch stub rather than the complete tracer the reviewer exists to provide.

A single fixed camera cannot recover an observed ball position after the ball becomes sub-pixel or disappears into clutter. Completing the visible path therefore requires an inference. The product distinction is not whether inference exists, but whether it is anchored to a real ball track, bounded, labelled and kept separate from measurements the camera cannot support.

## Decision

- Automatic display eligibility still begins with a confidence-gated, source-timed WASB-SBDT golf-ball track. Generic Vision motion, an audio transient, body movement or a default curve cannot pass this gate.
- A passing observed launch track may seed a deterministic image-space flight fit. The fit may continue through an inferred apex and bounded landing point, producing `.observedAndInferred` provenance.
- The rendered line must distinguish the observed and inferred portions. Product copy must state `Observed launch · estimated flight`, and accessibility descriptions must preserve that distinction.
- A clip without enough ball-specific observations still displays `Ball flight not tracked` and no automatic curve.
- A person may create or correct a path through the assisted editor. That path is user-authored, must be labelled `Manual trace`, and must never be described as automatically observed.
- Playback and rendered export consume the same stored, source-time geometry. Export must not rerun detection or replace the reviewed path.
- All selector and sampling windows use presentation timestamps and seconds or per-second units. Nominal frame rate is metadata only and cannot be used to manufacture media time.
- Range-session automatic acceptance remains stricter than one-shot tracing. A ball track is launch evidence, but the session may promote it only when the proposal is associated with the configured target golfer. Unresolved multi-golfer ownership remains uncertain.
- Numerical carry distance and apex height remain unavailable until capture calibration and representative known-ground-truth validation exist. A screen-space apex marker is geometry, not a height measurement.

## Alternatives considered

- **Observed points only:** maximally conservative, but cannot deliver a complete consumer tracer once the ball becomes visually unresolvable.
- **Always draw a fitted parabola:** rejected because it recreates the original incident on clips without ball evidence.
- **Treat generic Vision trajectories as the seed:** rejected because prior native probing followed unrelated club and scene motion.
- **Display distance from the image-space curve:** rejected because a single uncalibrated two-dimensional view cannot support that measurement.

## Consequences

- The reviewer can deliver a complete, shareable trace when it first establishes the ball, while retaining an explicit no-tracer state for unsupported footage.
- Users can rescue an automatic miss without the app misrepresenting their manual input as detection.
- Visual design and export require two coordinated line treatments and provenance copy.
- Held-out positive and negative footage, cross-rate detector results and physical-device performance remain release gates. Synthetic timebase tests prove only that the code does not change its decision because the same physical samples were indexed at a different nominal rate.
