# 002 — Keep the flight causal and land down-range

- **Status**: PARTIAL
- **Commit**: Pending checkpoint delivery
- **Severity**: HIGH
- **Category**: Purpose, physicality and timing
- **Estimated scope**: 6 files, approximately 220 lines including tests and context updates

## Problem

The exact `IMG_0495.mov` output fails the core broadcast-tracer illusion in two ways.

`Ronde iOS App/Domain/ShotReviewModels.swift:696-710` shortens the entire estimated flight whenever the source is shorter than the model:

```swift
let finalHold = min(0.30, available * 0.07)
let minimumEvidenceDuration = max(0.18, lastObservedTime - impactTime + 0.15)
return min(modelDuration, max(minimumEvidenceDuration, available - finalHold))
```

`FullFlightRevealTimeline` then distributes every continuation point uniformly over that shorter duration. On the supplied source, the model duration is about 5.04 seconds after impact but the presentation is compressed to about 4.38 seconds. The modelled apex therefore appears before the visible source ball reaches it. This is not causal trail behaviour.

`Ronde iOS App/Analysis/EvidenceAnchoredFlightPathExtrapolator.swift:340-353` applies the final observed model residual unchanged to every future point:

```swift
let joinOffset = (x: last.x - joinReference.x, y: last.y - joinReference.y)
// ...
x: projected.x + joinOffset.x,
y: projected.y + joinOffset.y
```

That treats a near-field residual as constant at long distance. A roughly one-per-cent observed leftward drift becomes a landing more than eleven per cent of the frame to the left, ending over the golfer at about `(0.404, 0.492)`. A down-the-line landing should converge towards the fitted vanishing region, not return towards foreground geometry or magnify detector jitter.

## Target

1. Preserve source timestamps exactly for observed points.
2. Preserve the model's uncompressed timing from impact through the estimated apex. If the source cannot contain the full model duration, compress only the post-apex descent.
3. Keep a causal trail lag through the apex and continuation. The visible ribbon head and apex marker must never lead the source ball on the supplied frame. Use the existing sampling-derived lag, with a 50 ms maximum; do not add decorative easing. Timeline interpolation remains linear because it represents media time.
4. Leave at most a 120 ms completed-path hold at source end. If the available source ends before the modelled apex plus causal lag, do not compress the ascent; withhold landing/carry rather than lead the ball.
5. Decay the detector-to-model join residual smoothly to zero as down-range distance increases. Use `residualWeight = pow(1 - progress, 2)` where `progress` is `0...1` from the last observed point to landing.
6. Bound lateral continuation from the final observed point using the robust observed displacement:
   - `observedDX = last.x - first.x`;
   - `maximumLandingDX = min(0.055, max(0.012, abs(observedDX) * 2.5 + 0.008))`;
   - retain the observed direction when `abs(observedDX) >= 0.002`;
   - blend any raw landing correction with `smoothstep(progress) = progress * progress * (3 - 2 * progress)` so the join remains exact and there is no kink;
   - keep the continuation inside the corridor between the last observation and bounded landing, plus 0.008 normalised padding.
7. A displayable estimated landing must remain on the distant-ground side of the fitted projection: below the horizon, above the launch point and inside the safe frame. Carry remains modelled and uncalibrated.
8. SwiftUI playback and exported MOV must use identical time-warp keyframes. `EST. APEX` appears only after the causal head reaches apex; `EST. LANDING` and carry appear only after landing.

## Repo conventions to follow

- `Ronde iOS App/Domain/ShotReviewModels.swift:682-919` owns the shared playback/export reveal chronology. Do not create a renderer-specific second clock.
- `Ronde iOS App/Analysis/EvidenceAnchoredFlightPathExtrapolator.swift:331-356` owns inferred continuation geometry. Detector-attributed points must not be edited.
- `Ronde iOS App/Features/AssistedTracerEditor.swift` and `Ronde iOS App/Media/TracedVideoExporter.swift` consume `FullFlightRevealTimeline`; keep their geometry and keyframes in parity.
- Motion is linear because it represents source/model time. Do not introduce UI easing or springs.
- Purple remains the only tracer hue. This plan does not restyle the ribbon.

## Steps

1. Extend `FullFlightRevealTimeline` to accept both the original model flight duration and an optional shorter presentation duration. Derive the continuation apex from the minimum image-space `y` and preserve original model timing through that sample.
2. When presentation is shorter, map only samples after apex into the remaining source time. Ensure every mapped sample time remains strictly increasing. Reserve no more than 120 ms for the final hold.
3. Simplify `visibleDistance(at:)`, `strokeRevealKeyframes()` and `revealTime(for:)` so continuation samples use their mapped source/model timestamps and retain causal lag. Do not re-normalise the whole continuation after observation.
4. Change `EvidenceAnchoredFlightPathExtrapolator.landingContinuation` to decay the join residual, cap lateral growth using the formula above and blend the correction with smoothstep. Preserve the exact last-observation join.
5. Update `EvidenceAnchoredFlightPathTests.swift` with deterministic cases proving: apex time is unchanged under short-source fitting; only descent is compressed; visible distance before apex remains behind the apex; final keyframes still reach one; a source too short to preserve apex does not lead; join residual reaches zero; lateral landing is bounded and directionally consistent.
6. Re-run the exact `IMG_0495.mov` diagnostic/export. Compare the source ball and purple head at the user's apex frame, and inspect final landing relative to the vanishing corridor. Record coordinates without claiming ground-truth carry.
7. Update ADR 0008, product contract, architecture, operations, current state, changelog and tracer validation ledger. Explicitly supersede the claim that uniform whole-continuation compression is acceptable.

## Boundaries

- Do not alter detector eligibility, observed points, source timestamps, impact analysis, launch-anchor detection, model weights, carry calculation or the one-video-under-60-seconds MVP.
- Do not fabricate a landing if the fitted geometry fails the new constraints.
- Do not add dependencies.
- Preserve manual trace behaviour and Reduced Motion behaviour.
- Preserve unrelated Supabase, persistence, app-shell, entitlement and Watch changes in the mixed working tree.
- If the cited source no longer matches commit `7f60902`, stop and report the drift instead of adding a parallel path.

## Verification

- **Mechanical**: run the focused `GolfBallTrackSelectorTests` and `EvidenceAnchoredFlightPathTests`, then the complete `Ronde iOS` Simulator suite. Expect zero failures. Run `git diff --check`, `./scripts/update-context-library.sh` and `./scripts/check-context-library.sh`.
- **Feel check**: export `IMG_0495.mov` and inspect frame by frame at impact, first observation, the user-marked near-apex frame, apex, descent and landing. Confirm:
  - the ribbon begins on the ball;
  - the head remains behind the visible ball through apex;
  - the apex label does not appear early;
  - the curve has no timing jump where descent compression begins;
  - the continuation does not magnify small lateral drift or return onto the golfer;
  - landing/carry appear only when the final path point is reached.
- **Done when**: the supplied screenshot failure is no longer reproducible, the landing converges down-range, and playback/export parity is covered by deterministic tests. The current implementation covers the timing and parity conditions, but the owner still rejects the visual result as off, so this remains partial.
