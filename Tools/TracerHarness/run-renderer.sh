#!/bin/zsh
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  Tools/TracerHarness/run-renderer.sh \
    --source /private/path/daylight.mov \
    --reference /private/path/daylight-reference.json \
    --output-dir /private/path/renderer/daylight

  Tools/TracerHarness/run-renderer.sh \
    --source /private/path/night.mov \
    --prediction /private/path/night-corridor.json \
    --output-dir /private/path/renderer/night-edgetam-corridor

Runs the exact production ShotVideoTrace/TimedTrajectoryPath/ShotVideoLayout/ShotVideoExporter
against the longest contiguous reviewed-visible reference block, or the longest contiguous
nonempty block from a canonical model prediction. The two input modes are mutually exclusive.
Prediction renders retain supplied assistance and model provenance and are not fully automatic.
EOF
}

script_dir=${0:A:h}
repo_root=${script_dir:h:h}
source_path=''
reference_path=''
prediction_path=''
output_dir=''

while (( $# > 0 )); do
  case "$1" in
    --source|--reference|--prediction|--output-dir)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      case "$1" in
        --source) source_path=$2 ;;
        --reference) reference_path=$2 ;;
        --prediction) prediction_path=$2 ;;
        --output-dir) output_dir=$2 ;;
      esac
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

[[ -n $source_path && -n $output_dir && ( -n $reference_path || -n $prediction_path ) ]] || { usage >&2; exit 2; }
[[ -z $reference_path || -z $prediction_path ]] || { print -u2 -- 'Reference and prediction inputs are mutually exclusive.'; exit 2; }
input_path=${reference_path:-$prediction_path}
[[ $source_path = /* && $input_path = /* && $output_dir = /* ]] || {
  print -u2 -- 'Source, input and output directory must be absolute paths.'
  exit 2
}
[[ -f $source_path ]] || { print -u2 -- 'Source video is not readable.'; exit 2; }
[[ -f $input_path ]] || { print -u2 -- 'Input JSON is not readable.'; exit 2; }

source_real=${source_path:A}
input_real=${input_path:A}
output_real=${output_dir:A}
repo_real=${repo_root:A}
case "$source_real/" in "$repo_real/"*) print -u2 -- 'Private source must be outside this repository.'; exit 2 ;; esac
case "$input_real/" in "$repo_real/"*) print -u2 -- 'Private input must be outside this repository.'; exit 2 ;; esac
case "$output_real/" in "$repo_real/"*) print -u2 -- 'Private renderer output must be outside this repository.'; exit 2 ;; esac

mkdir -p -- "$output_real"
build_root=$(mktemp -d "${TMPDIR:-/tmp}/ronde-renderer-build.XXXXXX")
trap 'rm -rf -- "$build_root"' EXIT INT TERM

source_hash="sha256:$(shasum -a 256 "$source_real" | awk '{print $1}')"
input_hash="sha256:$(shasum -a 256 "$input_real" | awk '{print $1}')"
renderer_hash="sha256:$( {
  for file in \
    "Ronde iOS App/Domain/ShotReviewModels.swift" \
    "Ronde iOS App/Domain/SeededModelTrace.swift" \
    "Tools/TracerHarness/Renderer/RendererReviewCandidateAdapter.swift" \
    "Ronde iOS App/Domain/ShotVideoEdit.swift" \
    "Ronde iOS App/Media/TracedVideoExporter.swift" \
    "Ronde iOS App/Media/ShotVideoExporter.swift" \
    "Tools/TracerHarness/Renderer/RendererOracle.swift" \
    "Tools/TracerHarness/run-renderer.sh"; do
    digest=$(shasum -a 256 "$repo_real/$file" | awk '{print $1}')
    printf '%s\t%s\n' "$file" "$digest"
  done
} | shasum -a 256 | awk '{print $1}')"

binary="$build_root/renderer-oracle"
xcrun swiftc -O -parse-as-library \
  -framework AVFoundation -framework CoreGraphics -framework CoreImage -framework CoreText \
  -framework ImageIO -framework QuartzCore \
  "$repo_real/Ronde iOS App/Domain/ShotReviewModels.swift" \
  "$repo_real/Ronde iOS App/Domain/SeededModelTrace.swift" \
  "$repo_real/Tools/TracerHarness/Renderer/RendererReviewCandidateAdapter.swift" \
  "$repo_real/Ronde iOS App/Domain/ShotVideoEdit.swift" \
  "$repo_real/Ronde iOS App/Media/TracedVideoExporter.swift" \
  "$repo_real/Ronde iOS App/Media/ShotVideoExporter.swift" \
  "$repo_real/Tools/TracerHarness/Renderer/RendererOracle.swift" \
  -o "$binary"

input_args=(--prediction "$input_real" --prediction-hash "$input_hash")
if [[ -n $reference_path ]]; then
  input_args=(--reference "$input_real" --reference-hash "$input_hash")
fi

"$binary" \
  --source "$source_real" \
  --output-dir "$output_real" \
  --repo-root "$repo_real" \
  --source-hash "$source_hash" \
  --renderer-hash "$renderer_hash" \
  "${input_args[@]}"
