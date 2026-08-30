# Animation plans

| Plan | Title | Severity | Status |
| --- | --- | --- | --- |
| [001](001-continuous-flight-reveal.md) | Reveal the tracer as one chronological flight | HIGH | DONE |
| [002](002-keep-flight-causal-and-land-downrange.md) | Keep the flight causal and land down-range | HIGH | PARTIAL |

## Execution order

1. Plan 001 is complete and supplies the shared playback/export timeline.
2. Plan 002 implemented its timing and continuation bounds, but the owner still rejects the exact-source visual result as off. Treat it as an experimental checkpoint, not an accepted accuracy fix.

Plan 002 is required because exact-source review exposed a timing lead at apex and a landing that magnified near-field residuals. Validate it against labelled source frames rather than accepting test-only geometry.
