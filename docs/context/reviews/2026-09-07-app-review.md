# Ronde app review, 7 September 2026

## Finding

The app needed a useful media workflow and a more honest accuracy boundary. The owner rejected the small scattered text and reported an inaccurate trajectory. The review reproduced component defects in tracking and archive recovery and found a fragmented Home/Library/Profile experience with no proper trim-to-share workflow. The redesign in ADR 0011 addresses the product structure and several deterministic defects. It does not close the real-video accuracy gate.

## Evidence and disposition

| Finding | Evidence | September change |
| --- | --- | --- |
| Accepted ball track could be replaced at finalisation | Production selector counterexample switched an established track to a shorter distant track | Preserve committed lineage and revalidate after trimming |
| Some source cadences starved acquisition | 32 fps could halve decode cadence and then halve acquisition again; 15/20 fps could fail gap/coverage gates | Phase-retaining sampler and elapsed-source-time acquisition |
| Tracking loss and apex reversal could truncate a valid path | Short link window conflicted with later reacquisition; directional gate rejected turning samples | Three-point guarded reacquisition and prediction-supported low-speed apex |
| Full-flight line looked authoritative beyond observed evidence | Extrapolation depends on uncalibrated camera/flight priors; owner rejected output | Active studio shows observed points only; manual remains separately labelled |
| Review UI fragmented into tiny metrics and controls | Source and Simulator inspection on iPhone/iPad, including accessibility text | One library, large media studio, grouped editing controls, native settings/details |
| Import/navigation and playback broke expected workflow | Import used global selection; Play restarted after pause | Typed prepared-import route and resumable playback |
| Missing trim and no-trace export path | Existing share relied on a tracer and complete candidate window | Non-destructive trim and fitted MP4 output with or without a line |
| Corrupt library could silently be overwritten | Production archive probe: invalid bytes loaded as empty and next save replaced them | Typed reads, blocked unsafe writes and visible retries |
| Delayed Photos import could cross account boundary | Ownership was captured after transfer | Capture generation before picker, check asynchronous work and cancel stale analysis |

## What Astra should work on next

1. Establish a labelled source-video benchmark before further model tuning. Measure acquisition recall, false-tracer rate, source-pixel error, visible-flight coverage and cost separately. Keep owner-selected regressions separate from held-out evaluation.
2. Compare a commercially distributable golf-specific detector against the existing tennis-domain model on exactly that benchmark. Check data, code and weight licences independently.
3. Add explicit social crop/reframe only with matching preview and ball-safe composition. Current fit export is a deliberate first step.
4. Complete cold offline account access and cloud metadata deletion reconciliation. These are independent reliability gaps, not solved by the redesign.
5. Validate the finished editor with representative golfers and physical devices. Simulator layouts and synthetic encoder tests do not measure usability or tracking accuracy.

No private footage, round data or account credentials belong in this record. The prior external audit artifacts and complete pre-cleanup Git bundle were retained outside the repository. Branch cleanup preserved all unique history before removing obsolete branch references.
