# 0003: Direct shot review, provisional markers and assisted tracer

**Status:** accepted; tracer rendering and native-feasibility portions superseded by ADR 0004

**Date:** 22 August 2026

## Context

The first reviewer slice treated every generic parabolic Vision observation as a swing candidate and screen-space tracer. A supplied 6.62-second one-swing clip produced 26 candidates and no useful ball-flight arc. The clip is portrait 4K at 30 fps: it contains enough human and impact evidence for a review marker, but not enough visible ball samples to establish the complete flight and landing.

## Decision

- Prefer strong impact-like audio transients for provisional timing, merge short audio clusters and apply a four-second refractory period.
- Fall back to sampled Vision human-body pose motion when audio is missing, empty or unreadable. Honour the video's preferred transform before body-pose analysis.
- Treat either signal as an uncertain review marker only. A person confirms shot/practice and may adjust the impact frame.
- Exclude generic `VNDetectTrajectoriesRequest` output from swing-candidate and tracer creation.
- For a short import with one detected swing, bypass segmentation UI and navigate directly from import into Shot Review.
- Display a complete estimated tracer immediately over the main video. Retain adjustable launch, apex and landing geometry in the active review session and keep numerical distance out of the interface.
- Reserve candidate queues, shot/practice decisions, manual markers and trim detail for multi-shot recordings.
- Remove vector, alignment and freehand annotation tools from the reviewer so playback and tracer adjustment own the interaction hierarchy.
- Keep automatic ball flight as a separate golf-ball-specific detector experiment requiring held-out footage, confidence thresholds and physical-device validation.

## Alternatives considered

- Increase the generic Vision cooldown only: rejected because it reduces duplicate symptoms without establishing that the moving object is a golf ball or even a swing.
- Present the estimated default arc as automatic observed tracking: rejected because 30 fps footage may not contain the observed landing. The visible default remains explicitly estimated and user-adjustable.
- Integrate YOLO or SAM immediately: deferred. A compact, permissively licensed ball detector remains a reasonable experiment, but it requires labelled golf footage, Core ML conversion and measured device performance. General segmentation is more useful for offline labelling than this first runtime.

## Consequences

- Short one-shot imports present one video-first Shot Review instead of a candidate-management wall.
- Long sessions still require false-positive measurement, especially when other golfers or range impacts are visible/audible.
- Body-motion timing is provisional and may land in follow-through rather than exact impact; the trim control remains essential.
- The assisted tracer is visible without setup and immediately useful for review, but it is not automatic tracking or a physical trajectory.
- Numerical carry distance remains out of scope until calibration and ground-truth comparison exist.
