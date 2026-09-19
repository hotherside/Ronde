# Renderer oracle

This harness exports a short, private reference-driven MP4 through the production
`ShotVideoTrace`, `TimedTrajectoryPath`, `ShotVideoLayout`, and `ShotVideoExporter` types. It
selects the longest contiguous run of visible points reviewed by an agent or human, preserving
the source PTS supplied by the reference JSON. It does not run automatic detection or claim
automatic tracer accuracy.

Run it from the repository with private inputs and an output directory outside the repository:

```sh
Tools/TracerHarness/run-renderer.sh \
  --source "/private/path/daylight.mov" \
  --reference "/private/path/daylight-reference.json" \
  --output-dir "/private/path/renderer/daylight"

# Canonical assisted detector prediction mode; --reference and --prediction are exclusive.
Tools/TracerHarness/run-renderer.sh \
  --source "/private/path/night.mov" \
  --prediction "/private/path/night-corridor.json" \
  --output-dir "/private/path/renderer/night-edgetam-corridor"
```

The output directory contains the MP4, three sample PNGs, and `manifest.json`. The manifest
records source/input/renderer hashes, the selected source-frame interval, annotation
provenance, fitted canvas geometry, assistance and model/checkpoint provenance, and output timing.
Prediction manifests retain prompt counts, crop/interval metadata, and the source input hash.
The decoder accepts a structured model object or a model name with flat checkpoint/code
hashes. Adaptive runs also retain model-derived reset counts and active dropout settings.
Frozen early gap inputs include an inherited default-policy string; their explicit
`activeGapPolicy` and source-time bound take precedence in the render sidecar, with the
original string retained for provenance. Rendering does not discard points because a
reference labels their timestamp uncertain or because localisation error is high.
Output PTS and image-generator sample
times are relative to the trimmed export; `outputActualSourceTimestamp` and
`sourceTimestampDelta` make that offset explicit.

`RendererReviewCandidateAdapter.swift` is a build-only container adapter. The complete app
`ReviewModels.swift` file has UI and persistence dependencies that are outside this macOS
oracle build, so the adapter supplies only the stored fields consumed by production
`ShotVideoTrace`. It does not copy or reimplement renderer logic.

The production exporter retains its `Observed ball track` burned label. Each private manifest
marks reference renders as reference-driven and detector renders as assisted predictions with
`referenceDriven: false`, `detectorPrediction: true`, `assisted: true`, and
`autonomousAcquisition: false`. The production `Observed ball track` label remains unchanged;
for detector renders it must be read alongside the sidecar's supplied point, crop, interval,
and model provenance. These outputs are not fully automatic or human-ground-truth evidence.
