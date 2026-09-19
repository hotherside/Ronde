# Synthetic studio fixture

`studio-fixture.mp4` is an original, generated test pattern, not golf footage. It is portrait 360 × 640 at 30 fps, about 6.67 seconds long, with a 440 Hz mono AAC tone. A white square at the upper left and violet square at the lower right expose rotation, fit and cropping mistakes. The green background provides a stable contrast field for trace pixel checks. It contains no people, personal data or location metadata.

Generate with FFmpeg:

```sh
ffmpeg -f lavfi -i 'color=c=0x476555:size=360x640:rate=30:duration=6.634' \
  -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=6.634' \
  -vf 'drawbox=x=18:y=18:w=60:h=60:color=white:t=fill,drawbox=x=282:y=562:w=60:h=60:color=0x7755ee:t=fill' \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest studio-fixture.mp4
```

This fixture tests editing and encoding, never ball detection accuracy.

## Populated concept review movies

`clubhouse-range.mp4` and `clubhouse-course.mp4` are 16-second, silent 960 × 640 H.264 movies made from the fictional still images in `docs/design/2026-09-19-shot-media/assets/`. See that directory's README for image provenance. They provide representative visual composition for the Debug-only populated review route; they contain no actual swing, observed ball flight or private media.

From the repository root, reproduce each with FFmpeg (replace `range` with `course` for the second file):

```sh
ffmpeg -loop 1 -i docs/design/2026-09-19-shot-media/assets/range.png -t 16 \
  -vf scale=960:640 -r 24 -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
  'Ronde iOS AppUITests/Resources/clubhouse-range.mp4'
```

The original test pattern remains the fixture for trimming, rotation and encoding checks.
