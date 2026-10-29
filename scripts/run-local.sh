#!/usr/bin/env bash
# Runs the immune cytometry workflows locally with Docker, the way a compute node
# would: each step's INPUT_DIR is assembled from the linked outputs of the steps
# before it (INPUT_DIR/<input>/ <- OUTPUT_DIR/<output>/ of the source; several
# links into one input land side by side), and each step writes its own
# OUTPUT_DIR. No Pennsieve account needed.
#
# Usage: scripts/run-local.sh <a|b|both> <input-dir-with-fcs-files> [work-dir]
#   a     Immune Profiling & Differential Abundance
#   b     Multi-batch Harmonization & QC
#   The sibling repos processor-* must be checked out next to this one.
#   MAX_EVENTS_PER_SAMPLE=20000 makes a quick run (prep subsamples every file).
set -euo pipefail
WHICH="$1"; IN="$(cd "$2" && pwd)"
WORK="$(mkdir -p "${3:-data/run}" && cd "${3:-data/run}" && pwd)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM="${PLATFORM:-linux/amd64}"
PREFIX="${IMAGE_PREFIX:-immune-cytometry}"

build() { # build <app>
  docker build --platform "$PLATFORM" -q -t "$PREFIX/$1" "$ROOT/../processor-$1" >/dev/null
  echo "built $PREFIX/$1"
}
link() { # link <step> <input> <source-step> <source-output|.>   (subfolder placement)
  # "." = an app with one output, which is the whole OUTPUT_DIR
  local dst="$WORK/$1/input/$2" src="$WORK/$3/output/$4"
  mkdir -p "$dst"
  [ -d "$src" ] && cp -R "$src/." "$dst/" || echo "   ($3 has no $4)"
}
fresh() { rm -rf "$WORK/$1"; mkdir -p "$WORK/$1/input" "$WORK/$1/output"; }
run() { # run <step> <app> [ENV=VAL ...]
  local step="$1" app="$2"; shift 2
  local envs=(); for e in "$@"; do envs+=(-e "$e"); done
  echo "== $step ($app)"; local t0; t0=$(date +%s)
  docker run --rm --platform "$PLATFORM" --memory "${MEMORY:-6g}" \
    -v "$WORK/$step/input:/data/input:ro" -v "$WORK/$step/output:/data/output" \
    -e INPUT_DIR=/data/input -e OUTPUT_DIR=/data/output ${envs[@]+"${envs[@]}"} "$PREFIX/$app" \
    > "$WORK/$step/log.txt" 2>&1 || { tail -30 "$WORK/$step/log.txt"; echo "!! $step failed"; exit 1; }
  echo "   done in $(( $(date +%s) - t0 ))s"
}

APPS=(fcs-prep peacoqc cytometry-report)
case "$WHICH" in
  a) APPS+=(cleanet flowsom cytometry-umap diffcyt) ;;
  b) APPS+=(cytometry-batch-assess cytonorm cycombine) ;;
  both) APPS+=(cleanet flowsom cytometry-umap diffcyt cytometry-batch-assess cytonorm cycombine) ;;
  *) echo "usage: $0 <a|b|both> <input-dir> [work-dir]" >&2; exit 2 ;;
esac
for a in "${APPS[@]}"; do build "$a"; done

# Shared head: prep (the selected files at the root) and PeacoQC.
fresh prep; cp -R "$IN/." "$WORK/prep/input/"
run prep fcs-prep MAX_EVENTS_PER_SAMPLE="${MAX_EVENTS_PER_SAMPLE:-0}"
fresh qc; link qc fcs prep fcs; link qc metadata prep metadata
run qc peacoqc

REF=(REFERENCE_COLUMN=control REFERENCE_VALUES=tcu1)

if [ "$WHICH" = a ] || [ "$WHICH" = both ]; then
  fresh doublets; link doublets fcs qc fcs; link doublets metadata prep metadata
  run doublets cleanet
  fresh clusters; link clusters fcs doublets fcs; link clusters metadata prep metadata
  run clusters flowsom
  fresh umap; link umap cells clusters cells; link umap metadata prep metadata
  run umap cytometry-umap
  fresh diffcyt; link diffcyt clusters clusters clusters; link diffcyt metadata prep metadata
  run diffcyt diffcyt CONDITION_COLUMN=condition REFERENCE_LEVEL=unstimulated BLOCK_COLUMN=batch
  fresh report-a
  link report-a metadata prep metadata; link report-a qc qc qc; link report-a doublets doublets qc
  link report-a clusters clusters clusters; link report-a embedding umap .
  link report-a da diffcyt da; link report-a ds diffcyt ds
  run report-a cytometry-report REPORT_TITLE="Immune Profiling & Differential Abundance"
  echo "Report A: $WORK/report-a/output/report/index.html"
fi

if [ "$WHICH" = b ] || [ "$WHICH" = both ]; then
  fresh assess-raw; link assess-raw fcs qc fcs; link assess-raw metadata prep metadata
  run assess-raw cytometry-batch-assess LABEL=raw "${REF[@]}"
  fresh cytonorm; link cytonorm fcs qc fcs; link cytonorm metadata prep metadata
  run cytonorm cytonorm MODE=controls BATCH_COLUMN=batch "${REF[@]}"
  fresh cycombine; link cycombine fcs qc fcs; link cycombine metadata prep metadata
  run cycombine cycombine BATCH_COLUMN=batch COVARIATE_COLUMN=condition
  for m in cytonorm cycombine; do
    fresh "assess-$m"; link "assess-$m" fcs "$m" fcs; link "assess-$m" metadata prep metadata
    run "assess-$m" cytometry-batch-assess LABEL="$m" "${REF[@]}"
  done
  fresh report-b
  link report-b metadata prep metadata; link report-b qc qc qc
  for s in assess-raw assess-cytonorm assess-cycombine; do link report-b assessment "$s" .; done
  for m in cytonorm cycombine; do link report-b normalization "$m" qc; done
  run report-b cytometry-report REPORT_TITLE="Multi-batch Harmonization & QC"
  echo "Report B: $WORK/report-b/output/report/index.html"
fi
