#!/bin/zsh
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  Tools/TracerHarness/run-tracker.sh \
    --media /absolute/path/to/video.mov \
    --model /absolute/path/to/GolfBallTracker.mlpackage \
    --impact 1.25 \
    --output-dir /absolute/private/output-directory \
    [--label daylight] [--cadence 0.0333333333] [--reacquisition 0.28] \
    [--peaks-per-tile 3 --variant multi-peak3 --tile-origin 0.25,0.50]

Runs the exact repository tracker, selector and domain types on macOS. Output is deliberately
required and must be outside this repository because it may contain private media timestamps and
coordinates. `--impact` is a controlled source timestamp in seconds; automatic impact detection is
not part of this harness.
EOF
}

script_dir=${0:A:h}
repo_root=${script_dir:h:h}
media=''
model=''
output_dir=''
impact=''
label=''
variant=''
cadence=''
reacquisition=''
peaks_per_tile=''
tile_origins=()

while (( $# > 0 )); do
  case "$1" in
    --media|--model|--output-dir|--impact|--label|--variant|--cadence|--reacquisition|--peaks-per-tile)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      case "$1" in
        --media) media=$2 ;;
        --model) model=$2 ;;
        --output-dir) output_dir=$2 ;;
        --impact) impact=$2 ;;
        --label) label=$2 ;;
        --variant) variant=$2 ;;
        --cadence) cadence=$2 ;;
        --reacquisition) reacquisition=$2 ;;
        --peaks-per-tile) peaks_per_tile=$2 ;;
      esac
      shift 2
      ;;
    --tile-origin)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      tile_origins+=("$2")
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n $media && -n $model && -n $output_dir && -n $impact ]] || { usage >&2; exit 2; }
[[ $media = /* && $model = /* && $output_dir = /* ]] || {
  print -u2 -- 'Media, model and output directory must be absolute paths.'
  exit 2
}
[[ -f $media ]] || { print -u2 -- 'Media file is not readable.'; exit 2; }
[[ -e $model ]] || { print -u2 -- 'Model path is not readable.'; exit 2; }

output_real=${output_dir:A}
repo_real=${repo_root:A}
case "$output_real/" in
  "$repo_real/"*)
    print -u2 -- 'Output directory must be outside this repository.'
    exit 2
    ;;
esac
mkdir -p -- "$output_real"

build_dir=$(mktemp -d "$output_real/.tracer-harness-build.XXXXXX")

bundle_tree_sha256() {
  local bundle_root=$1
  (
    cd "$bundle_root"
    find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
      local digest
      digest=$(shasum -a 256 "$file" | awk '{print $1}')
      printf '%s\t%s\n' "${file#./}" "$digest"
    done
  ) | shasum -a 256 | awk '{print $1}'
}

if [[ $model == *.mlpackage ]]; then
  compiled_root=$(mktemp -d "$output_real/.tracer-harness-model.XXXXXX")
  xcrun coremlcompiler compile "$model" "$compiled_root"
  model_name=${model:t:r}
  compiled_model="$compiled_root/$model_name.mlmodelc"
  [[ -d $compiled_model ]] || { print -u2 -- 'Core ML model compilation did not produce an mlmodelc bundle.'; exit 1; }
  weight_path="$model/Data/com.apple.CoreML/weights/weight.bin"
else
  [[ $model == *.mlmodelc && -d $model ]] || {
    print -u2 -- 'Model must be an .mlpackage or compiled .mlmodelc directory.'
    exit 2
  }
  compiled_model=$model
  weight_path=''
fi

model_bundle_sha256=$(bundle_tree_sha256 "$model")
model_weight_sha256=''
[[ -n $weight_path && -f $weight_path ]] && model_weight_sha256=$(shasum -a 256 "$weight_path" | awk '{print $1}')

binary="$build_dir/tracer-harness"
xcrun swiftc -O -parse-as-library \
  -framework AVFoundation -framework Accelerate -framework CoreGraphics -framework CoreImage \
  -framework CoreML -framework CoreVideo \
  "$repo_root/Ronde iOS App/Domain/ShotReviewModels.swift" \
  "$repo_root/Ronde iOS App/Analysis/GolfBallTrackSelector.swift" \
  "$repo_root/Ronde iOS App/Analysis/WASBGolfBallTrackingService.swift" \
  "$repo_root/Tools/TracerHarness/Swift/TracerHarness.swift" \
  -o "$binary"

source_hashes=()
for source in \
  'Ronde iOS App/Domain/ShotReviewModels.swift' \
  'Ronde iOS App/Analysis/GolfBallTrackSelector.swift' \
  'Ronde iOS App/Analysis/WASBGolfBallTrackingService.swift'; do
  source_hashes+=(--source-hash "$source=$(shasum -a 256 "$repo_root/$source" | awk '{print $1}')")
done

arguments=(
  --media "$media"
  --model "$compiled_model"
  --output-dir "$output_real"
  --impact "$impact"
  --source-revision "$(git -C "$repo_root" rev-parse HEAD)"
  --media-sha256 "$(shasum -a 256 "$media" | awk '{print $1}')"
  --model-sha256 "$model_bundle_sha256"
)
[[ -n $model_weight_sha256 ]] && arguments+=(--model-weight-sha256 "$model_weight_sha256")
variant_descriptor='controlled-impact'
[[ -n $label ]] && variant_descriptor+="::$label"
[[ -n $variant ]] && variant_descriptor+="::$variant"
arguments+=(--variant "$variant_descriptor")
[[ -n $cadence ]] && arguments+=(--cadence "$cadence")
[[ -n $reacquisition ]] && arguments+=(--reacquisition "$reacquisition")
[[ -n $peaks_per_tile ]] && arguments+=(--peaks-per-tile "$peaks_per_tile")
for origin in "${tile_origins[@]}"; do
  arguments+=(--tile-origin "$origin")
done

"$binary" "${arguments[@]}" "${source_hashes[@]}"
