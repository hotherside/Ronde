# Tracer benchmark harness

This directory separates detection, association and rendering with reproducible source-timed evidence. It includes an exact-source Swift tracker runner, reference-crop extractor, standard-library Python scorer and isolated comparison adapters. Keep real source video, frame manifests, labels, predictions, models and reports outside this repository. Only synthetic fixtures under `examples/` belong in Git.

## Workflow

1. Preserve the original source and record its hash, upright dimensions and actual AVFoundation presentation timestamps. Never reconstruct time from frame index or nominal FPS.
2. Inspect native source crops and label visible ball centres with visibility, uncertainty and review provenance. Mark uncertain frames without coordinates. Crop-placement anchors are inspection aids, not reference observations.
3. Run the production tracker with explicit assistance recorded, convert its diagnostic output and score it against the reference. Inspect wrong positions and raw candidate recall separately.
4. Freeze each experiment before scoring. Declare point prompts, supplied time intervals, crop corridors and corrections. Use held-out footage before adoption.
5. Feed reviewed reference points through the [production renderer harness](Renderer/README.md) to inspect drawing separately from detection. Then use the [standalone device probe](Device/README.md) to measure the actual pipeline on a signed phone; Mac and Simulator results do not establish phone latency, memory or thermals.

## Exact-source tracker

The macOS runner compiles the repository's tracker, selector and domain sources. It requires Xcode command-line tools and takes either an `.mlpackage` or compiled `.mlmodelc` bundle. The following impact value is illustrative:

```sh
Tools/TracerHarness/run-tracker.sh \
  --media /private/review/source.mov \
  --model "$PWD/Ronde iOS App/Resources/GolfBallTracker.mlpackage" \
  --impact 1.25 \
  --output-dir /private/review/baseline

python3 Tools/TracerHarness/python/import_tracker_result.py \
  --run-directory /private/review/baseline \
  --clip-id owner-positive-01 \
  --output /private/review/baseline/prediction.json
```

`manifest.json` records source metadata, actual source PTS, source revision plus source-file hashes, model hash scope, whole model-bundle hash and weight hash when available, configuration and assistance. `frames.ndjson` contains raw candidates, search/gate state and optional selected candidates for every model window. `result.json` contains the final selected path and aggregate instrumentation. Per-window selections need not all survive final path selection. `trackConfidence` on final positions is the repeated whole-track score; raw candidate `detectorConfidence` is a different quantity.

The runner's supplied impact time makes this an assisted comparison, even with no spatial prompt. `--peaks-per-tile 3` is a diagnostic variant only; the application default remains one. `--tile-origin` supplies a diagnostic search corridor and must be declared as extra assistance. No harness result validates automatic impact discovery.

## Native reference crops

Compile `Reference/ExtractReferenceFrames.swift` with an absolute source-file path, placing the binary outside the checkout:

```sh
xcrun swiftc -O -parse-as-library \
  -framework AVFoundation -framework CoreImage -framework ImageIO \
  "$PWD/Tools/TracerHarness/Reference/ExtractReferenceFrames.swift" \
  -o /private/review/extract-reference

/private/review/extract-reference \
  /private/review/source.mov /private/review/crop-config.json /private/review/crops
```

The private configuration contains `start`, `end`, `cropSize`, an `anchors` array of `{timestamp,x,y}` in upright source pixels and an `overviewTimes` array (which may be empty). Anchors only place native square inspection crops. Their interpolated centres never become labels. The output manifest records each actual source PTS, frame index and crop origin. Use these offsets to map an independently reviewed crop centre back to the source image.

The [alternative model adapter](alternatives/README.md) uses the same coordinate/time contract and records additional assistance. `alternatives/seeded_candidate_replay.py` re-associates existing raw candidates with one supplied ball point; it cannot recover a detection absent from that pool or establish acquisition outside the original search regions.

Run the synthetic scorer regressions with `python3 -m unittest discover -s Tools/TracerHarness/python -p 'test_*.py'`.

## Reference schema

`reference.json` describes labels at actual source presentation timestamps. It is deliberately a reference annotation rather than blanket “ground truth”. The required root fields are:

```json
{
  "schemaVersion": "1.0",
  "clipId": "synthetic-visible-gap",
  "sourceHash": "sha256:synthetic",
  "width": 1920,
  "height": 1080,
  "coordinateOrigin": "top-left",
  "coordinateSpace": "normalized",
  "frames": [
    {
      "timestamp": 1.234,
      "x": 0.42,
      "y": 0.31,
      "visibility": "visible",
      "reviewStatus": "agent-reviewed",
      "uncertaintyPx": 4.0
    },
    {
      "timestamp": 1.267,
      "visibility": "occluded",
      "reviewStatus": "human-verified"
    }
  ]
}
```

`timestamp` is the source PTS in seconds. Do not reconstruct it from nominal FPS. `visibility` is one of `visible`, `occluded`, `out_of_frame`, `uncertain` or `not_launched`. Visible labels require normalised `x` and `y` in the top-left coordinate system. `uncertaintyPx` is optional and applies to visible labels. `reviewStatus` is one of `human-verified`, `agent-reviewed`, `proposal` or `unreviewed`; the scorer reports these provenance groups separately. The reviewed-coverage subset includes agent-reviewed and human-verified labels. Proposal and unreviewed labels remain visible in the overall reference counts but are not treated as independently verified.

`sourceHash` must use the `sha256:` prefix. The scorer requires clip ID, source hash, dimensions and coordinate metadata to match exactly between reference and prediction. Reference and final-track timestamps must be strictly increasing; candidate timestamps may repeat at one PTS but must be non-decreasing.

## Prediction schema

`prediction.json` uses the same source metadata and has source-timed predicted samples:

```json
{
  "schemaVersion": "1.0",
  "clipId": "synthetic-visible-gap",
  "sourceHash": "sha256:synthetic",
  "width": 1920,
  "height": 1080,
  "coordinateOrigin": "top-left",
  "coordinateSpace": "normalized",
  "mode": "automatic",
  "promptCount": 0,
  "correctionCount": 0,
  "frames": [{"timestamp": 1.234, "x": 0.421, "y": 0.309}],
  "candidates": [{"timestamp": 1.234, "x": 0.421, "y": 0.309}]
}
```

`mode` is `automatic` or `assisted`; `promptCount` and `correctionCount` are retained in every report. `candidates` is optional. When present, the scorer reports candidate recall against visible reference labels using the configured hit tolerance. Candidates sharing one source PTS are evaluated together using the minimum pixel error; each timestamp group can satisfy at most one reference frame. Both matching paths maximise the number of monotonic one-to-one timestamp pairs within an explicit tolerance, then minimise total time error. They never interpolate across source-PTS gaps. Reports retain an allowlist of source/model/checkpoint/code provenance; private prompt coordinates and paths are excluded.

`longestMissingInterval` is the source-time span from the first to last label in a contiguous run of unmatched visible labels. Any `occluded`, `out_of_frame`, `uncertain` or `not_launched` label breaks that run; the scorer never bridges a non-visible interval. A single missing labelled source PTS therefore has a zero-second span. `longestWrongLocalisationInterval` reports the equivalent source-time runs for timestamp-matched visible labels outside the absolute or uncertainty-aware threshold.

Run:

```sh
python3 Tools/TracerHarness/python/benchmark.py \
  --reference /private/path/reference.json \
  --prediction /private/path/prediction.json \
  --tolerance-ms 20 \
  --hit-tolerance-px 12
```

Use `--format json` for an aggregate machine-readable report or `--report /private/path/report.json` to write one outside the repository. Reports contain counts and aggregate error statistics, never private coordinates.

The report separates timestamp availability from localisation quality. `visible.coverage` is timestamp availability (`matchedVisibleFrames / visibleFrames`), while `visible.localisationHitsWithinTolerance.*.coverageReviewedVisible` is within-threshold coverage over every reviewed visible label, so a missing prediction counts as a miss. `visible.onTimeButWrong` counts samples with a timestamp match whose pixel error is outside the absolute or uncertainty-aware threshold. Raw median/p95/max pixel errors and absolute-tolerance hits are always retained even when an uncertainty-aware threshold also accepts a sample; `uncertaintyAware.acceptedOnlyByUncertainty` makes that difference explicit.
