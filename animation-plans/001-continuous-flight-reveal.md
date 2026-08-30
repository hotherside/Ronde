# 001 — Reveal the tracer as one chronological flight

- **Status**: DONE
- **Commit**: d5e67af
- **Severity**: HIGH
- **Category**: Purpose, cohesion and timing
- **Estimated scope**: 6 files, approximately 250 lines including tests and context updates

## Problem

The current implementation preserves evidence provenance by changing the order in which geometry appears. That makes one golf shot look like separate drawings.

`Ronde iOS App/Features/AssistedTracerEditor.swift:101` waits until the observed segment has finished before making either estimated segment visible:

```swift
private var estimatedGeometryRevealTime: TimeInterval {
    timedObservedPath.map { $0.endTime + $0.suggestedTrailLag }
        ?? (impactTime + flightDuration)
}
```

`Ronde iOS App/Features/AssistedTracerEditor.swift:300` then draws the complete launch connector and complete continuation together at that later time. `Ronde iOS App/Media/TracedVideoExporter.swift:277-324` repeats the same ordering by revealing both estimated segments statically after `observedTrailEndTime`.

The result is visually incorrect even though the points are labelled honestly: the mid-air observed stroke appears first, followed by an earlier launch connector and a later landing continuation. The trace also uses separate paths at the provenance boundaries, making joins easier to perceive as seams.

## Target

Render one continuous, source-time flight in chronological order:

1. A continuous purple launch ribbon reveals from the impact timestamp to the first observed timestamp.
2. The observed portion continues from the same join and remains behind the visible source ball by `TimedTrajectoryPath.suggestedTrailLag`.
3. The same ribbon continues from the observed endpoint towards landing over the modelled remaining flight time.
4. Geometry is smoothed once across the combined launch, observation and continuation point sequence. The rendered result must read as one tapered broadcast-style tracer without dashes, a colour break or a visible seam. Provenance is communicated by a subtle opacity reduction on estimated spans plus explicit `EST.` and `MODEL CARRY` labelling; it must not change chronology.
5. The estimated apex marker appears when the chronological reveal reaches the apex. `MODEL CARRY` may appear at landing, not before the full estimate has been drawn.
6. Playback and exported MOV use the same timeline and cumulative-path mapping. Timeline movement is linear because it represents source/media time. Do not add decorative easing.
7. Reduced Motion removes progressive movement but still reveals the complete path only after impact, retaining the same continuous ribbon and explicit estimate labels.

## Repo conventions to follow

- `Ronde iOS App/Domain/ShotReviewModels.swift:446-606` already treats source presentation time as authoritative and maps time to cumulative screen-path distance.
- `Ronde iOS App/Features/AssistedTracerEditor.swift` owns the SwiftUI/Canvas rendering surface.
- `Ronde iOS App/Media/TracedVideoExporter.swift` owns the equivalent Core Animation rendering and must not rerun detection.
- Automatic detector points remain observed evidence. Renderer interpolation and estimated connector/continuation points must not be relabelled as observed.
- Purple remains the only tracer hue. The line is continuous; estimated spans may be modestly less opaque but must not look like separate geometry.

## Steps

1. In `Ronde iOS App/Domain/ShotReviewModels.swift`, add a renderer-only full-flight timeline that accepts impact time, launch connector, observed points with source timestamps, continuation, and estimated total flight duration. It must validate monotonic times and expose one smoothed cumulative path plus exact cumulative-distance ranges for launch, observed and continuation provenance.
2. Assign launch-connector sample times monotonically over `impactTime...firstObservedTime`. Preserve the detector timestamps exactly for observed samples. Assign continuation sample times monotonically over `lastObservedTime...(impactTime + estimatedFlightDuration)`. Deduplicate shared join points and keep chronological order.
3. Add a time-to-visible-distance function. Before impact it returns zero. During estimated launch it advances only through the launch range. During observation it follows detector PTS and applies `suggestedTrailLag`. After observation it advances continuously through the estimated continuation. It must never jump backwards or reveal a later segment before an earlier segment.
4. In `AssistedTracerEditor.swift`, replace `estimatedGeometryRevealTime`, the bulk `estimatedGeometryOpacity`, and the three independently constructed paths with the shared full-flight timeline. Draw trims of the same smoothed path as one tapered solid-purple ribbon. Estimated ranges may use a modest opacity reduction, but no dash pattern or visible seam. Keep carry hidden until landing and show `EST. APEX` when the reveal reaches its timestamp.
5. In `TracedVideoExporter.swift`, build the identical full-flight timeline. Use Core Animation keyframes derived from source/model times and cumulative path distance. Each provenance layer must expose only its assigned range of the same path. Remove the late static fade-in of the full connector and continuation.
6. Update `EvidenceAnchoredFlightPathTests.swift` with deterministic tests proving chronological launch-observed-continuation ordering, continuity at both joins, monotonic reveal, no future observed point, and equivalent playback/export keyframes. Add a test showing that at a time inside observation the launch connector is complete, observation is partial and continuation is still hidden.
7. Amend ADR 0008, the product contract, current state, architecture, changelog and tracer validation ledger. Remove the now-rejected rule that all estimated geometry waits until observation ends. Record that provenance is styling while timing remains chronological.

## Boundaries

- Do not change the detector, acquisition thresholds, impact analyser, perspective fit or carry calculation in this plan.
- Do not fabricate observations or relabel inferred geometry.
- Do not add dependencies.
- Preserve manual trace behaviour.
- Preserve unrelated Supabase, persistence, app-shell and Watch changes in the mixed working tree.
- If the current source no longer matches the cited structures, stop and report instead of inventing a parallel rendering path.

## Verification

- **Mechanical**: run the focused evidence-anchored flight tests, then the complete `Ronde iOS` Simulator suite. Expect zero failures. Run `git diff --check`, `./scripts/update-context-library.sh` and `./scripts/check-context-library.sh`.
- **Feel check**: export the supplied `IMG_0495.mov`, inspect frame-by-frame from impact through landing and confirm:
  - the ribbon begins at launch and grows continuously;
  - provenance boundaries do not create a jump, dash break or colour seam;
  - the observed head never reaches or passes the visible ball;
  - the continuation begins only after the observed segment reaches its endpoint;
  - the apex marker appears when the reveal reaches the apex;
  - the complete path never appears in a second bulk step.
- **Done when**: the tracer reads as one uninterrupted flight from start to landing, while colour/style still distinguish observed evidence from estimation.
