# 0004: Source-time tracer and honest native tracking baseline

**Status:** accepted

**Date:** 22 August 2026

## Context

The first assisted tracer was a complete static curve, so it did not behave like a golf shot tracer during playback. The supplied 6.618-second portrait MOV also exposed a broken timing anchor: its dual AAC layout fell through to a 5.352-second body-motion marker even though visible and audio impact occur around 1.717 seconds. The user requires every uploaded frame rate to be accepted and wants evidence before choosing YOLO, ByteTrack or another open model.

## Decision

- Use the uploaded asset's presentation timestamps and preferred orientation as authority. Nominal frame rate influences available evidence and confidence only; it never rejects an import.
- Decode the preferred stereo audio track to PCM, cluster impact peaks and retain the existing body-motion fallback only when audio cannot produce a marker.
- Drive tracer reveal from `AVPlayer` item time: hidden before impact, progressively revealed through an estimated flight duration, held after completion and reset after seeking backwards.
- Automatically play a short single-shot review once. Keep Replay prominent and timing correction collapsed; remove path-drawing and adjustment controls from the primary review.
- Run generic native Vision trajectory analysis only as a bounded feasibility baseline after impact. It may supply provisional geometry but can never be labelled as observed golf-ball flight.
- Retain an explicitly inferred launch/apex/landing path whenever a defensible ball track is unavailable. Do not display numerical distance.
- Require a golf-ball-specific detector plus at least three continuity-gated post-impact observations before any future solid `Observed` segment. Evaluate a compact permissive detector before deciding whether ByteTrack-style temporal association adds value.

## Alternatives considered

- Keep the complete arc static: rejected because it does not communicate flight through time and does not reset correctly on replay or scrubbing.
- Require 60 or 120 fps: rejected as an import rule. Higher frame rates may improve trackability, but the app must process the file the user selected and degrade honestly.
- Label generic Vision trajectories as observed: rejected because trajectory detection does not establish that the object is a golf ball.
- Integrate YOLO and ByteTrack immediately: deferred until the native baseline and supplied clip establish the failure mode. The next experiment needs representative positive and negative footage, licence review and physical-device performance measurement.

## Consequences

- The supplied clip now receives one impact marker near the strike and a smooth estimated tracer during playback.
- The sample remains a graceful-degradation case: no reliable multi-frame outbound ball track or landing is visible, so no observed or distance claim is made.
- The app has a useful native playback MVP and a clear model boundary, but automatic observed tracking remains unfinished.
- Simulator tests and a private-sample visual check validate rendering and timing logic; physical-device import, thermal behaviour and model quality remain release gates.
