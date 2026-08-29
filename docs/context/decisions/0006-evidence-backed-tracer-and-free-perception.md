# 0006: Evidence-backed automatic tracers and free on-device perception

- **Status:** accepted
- **Date:** 24 August 2026
- **Supersedes:** the automatic inferred fallback accepted in parts of ADR 0004

## Context

Different uploaded videos displayed the same curve. Inspection and a native probe against the private 6.618-second sample found that the trajectory service passed Vision a bare `CVPixelBuffer`, losing the `CMSampleBuffer` presentation timestamp required by the stateful request. It then assigned that media time to `targetFrameTime`, which Apple defines as a real-time processing deadline. Vision returned error 18, `No valid presentationTimeStamp`, for every frame. The service swallowed the errors and returned fixed launch, apex and landing coordinates.

Correctly passing sample buffers made generic Vision return thousands of moving-shape observations, but the highest-scoring path followed unrelated motion including the club. `VNDetectTrajectoriesRequest` detects parabolic shapes; it does not establish golf-ball identity. A tracker such as ByteTrack also cannot supply identity without detector observations.

The product must remain local and incur no inference-service fee. Detector code and weights must also be safe to distribute commercially. A full-grid experiment found that the official WASB-SBDT tennis model detected the supplied golf ball in source-resolution tiles, and a signed iOS probe reproduced the track through the packaged Core ML model.

## Decision

- Pass `CMSampleBuffer` values to `VNSequenceRequestHandler` and do not use `targetFrameTime` as a media timestamp.
- Remove fixed automatic tracer geometry. When no ball-specific track passes the evidence threshold, return and display an unavailable state and draw no line.
- Treat generic Vision trajectories as diagnostics only. They cannot make `BallFlightEstimate.isDisplayable` true.
- Require a displayable tracer to contain at least three observed ball points, an observed trajectory and an observed or observed-plus-inferred provenance state.
- Package the official NTT Communications WASB-SBDT tennis weights under their MIT licence as a 2.6 MB Core ML model. The model consumes three consecutive RGB frames and returns a heatmap for the newest frame.
- Evaluate the model in overlapping 512 by 288 source-resolution tiles. Apply peak thresholding and cross-tile suppression, then use a purpose-built single-ball linker that requires at least seven post-impact detections, consecutive-frame coverage, minimum displacement and stable direction. ByteTrack is not required for this single-object lane.
- Render only the observed model points and their source presentation times. Do not turn the visible rising segment into a projected apex or landing path.
- Treat ByteTrack as association, not detection. Treat SAM-style foundation models as optional offline annotation aids, not an iPhone runtime dependency.
- Do not distribute Ultralytics AGPL code or weights as the default free lane.
- Keep release claims gated even though the model is integrated. One positive clip proves feasibility, not general golf-ball accuracy. Held-out positive and negative metrics, false-tracer rate and physical-device latency remain required before production release.

The official PyTorch weight SHA-256 is `9d391239ab10c733f8e5bfadf16ab72838e7a8ebc88e8ae2038501c03d42b4bb`; the converted Core ML weight SHA-256 is `508eec685ff6f8d20667d739ed0f3038a20d37de4121056a1b4f537c5564f8ee`. The upstream licence and notice ship beside the model.

## Consequences

- Ronde stops showing a superficially complete tracer on unsupported footage. A one-shot import shows the observed polyline only when the detector and linker pass; otherwise it shows no tracer.
- The existing source-time reveal renderer now consumes the detected point timestamps and follows the observed segment instead of inventing a complete arc.
- High-resolution crops and temporal continuity matter more than swapping detector brand names because a golf ball may occupy only a few pixels in a 4K portrait frame.
- The signed Simulator probe tracked 16 consecutive source-timed points from 2.018 to 2.518 seconds on the supplied private clip, with normalised motion from `(0.5606, 0.3422)` to `(0.5347, 0.2854)` and peak confidence `0.679`. The clip was removed after the probe and is not part of the repository.
- The runtime is free and local, but consented validation footage, negative testing and physical-device performance remain real release work.
