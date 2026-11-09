#!/usr/bin/env bash
# Full Quartus compile of the core and a summary of area and timing.
# Uses quartus_sh on PATH, else the pinned Quartus Lite 17.0.2 image.
# Output: output_files/M20.rbf and output_files/summary.txt.
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
image="${QUARTUS_IMAGE:-theypsilon/quartus-lite-c5@sha256:f638634df509786bc7507dbcb45673acd6adf32e5278c7b4e64ce67ae8ac2c70}"

quartus() {
  if command -v "$1" >/dev/null 2>&1; then
    (cd "${repo}" && "$@")
  else
    docker run --rm --user "$(id -u):$(id -g)" --volume "${repo}:/work" --workdir /work \
      "${image}" "/opt/intelFPGA_lite/quartus/bin/$1" "${@:2}"
  fi
}

mkdir -p "${repo}/output_files"
quartus quartus_sh --flow compile M20 > "${repo}/output_files/flow.log" 2>&1 ||
  { tail -60 "${repo}/output_files/flow.log"; exit 1; }

out="${repo}/output_files"
{
  echo "M20 $(date -I)"
  grep -E 'Logic utilization|Total registers|Total block memory bits|Total RAM Blocks|Total DSP Blocks|Total PLLs' "${out}/M20.fit.summary"
  for t in 'Fmax Summary' 'Setup Summary' 'Hold Summary' 'Recovery Summary' 'Removal Summary'; do
    grep -A14 "^; ${t} " "${out}/M20.sta.rpt" | grep -E '^; ' | grep -v "^; ${t}"
  done
} > "${out}/summary.txt"
cat "${out}/summary.txt"
