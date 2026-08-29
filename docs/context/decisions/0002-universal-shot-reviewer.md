# 0002: Universal iPhone/iPad Shot Reviewer boundary

**Status:** accepted

**Updated:** annotation, tracer and provisional-candidate mechanics are superseded by [ADR 0003](0003-review-markers-and-assisted-tracer.md).

**Date:** 21 August 2026

## Context

Ronde's committed product is an independent Apple Watch golf shot counter. The next product need is range-video review: cut long sessions into swing clips, provide a hands-free one-shot review loop, draw quick overlays and show a useful ball path. The previous iOS target was only a packaging stub. Automatic vision quality, physical-device performance and numerical distance are not yet established.

## Decision

- Keep the Watch app independent and preserve its offline shot-counter contract.
- Evolve the iOS packaging target into one universal iPhone/iPad, light-theme Shot Reviewer using adaptive SwiftUI layouts.
- Support Range Session import/record and Live Review with a bounded temporary rolling buffer. A candidate defaults to impact minus five seconds through impact plus five seconds; unrelated temporary media is discarded.
- Keep likely shots, practice swings and uncertain candidates recoverable for user correction. Do not auto-delete or auto-export candidates.
- Provide fixed vector/freehand annotations in normalised video coordinates. Automatic tracking is out of scope for the first implementation.
- Use Apple-native AVFoundation, Vision, Core ML/Create ML and PencilKit foundations, with local-only MVP processing and honest unsupported/low-confidence states.
- Show only a confidence-gated observed 2D tracer. Numerical distance requires a later calibration and known-ground-truth validation gate.

The fixed-annotation and first tracer decisions above are retained as decision history but are no longer the active reviewer contract. ADR 0003 removes the annotation surface and establishes direct single-shot tracer playback.

## Alternatives considered

- Keep iOS as a minimal companion: rejected because range review requires a first-class phone/tablet surface.
- Upload videos to a cloud model: rejected for MVP due to privacy, latency and operational complexity.
- Treat every trajectory as yardage: rejected because uncalibrated single-camera footage cannot support reliable physical distance.
- Automatically discard practice or uncertain swings: rejected because false negatives are costly and user correction is required.

## Consequences

- `project.yml` targets iPhone and iPad, permits multitasking, enforces light appearance and declares capture/import/export privacy strings.
- The generated Xcode project must be regenerated and reviewed after configuration integration; this decision does not claim that generated output is current.
- Camera/tracer/model success requires fixed-tripod physical-device evidence. Simulator builds are not sufficient.
- No numerical distance, automatic annotation tracking, cloud processing or automatic export is part of the MVP contract.
