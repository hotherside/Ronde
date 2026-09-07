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
