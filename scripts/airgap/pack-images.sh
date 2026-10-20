#!/usr/bin/env bash
# Air-gap helper: save/load the container images the recipes use (pinned by recipes/versions.lock).
#   scripts/airgap/pack-images.sh save OUTDIR [ids...]   # on a connected host: ids default = all lock entries
#   scripts/airgap/pack-images.sh load OUTDIR            # on the air-gapped host
# Weights travel separately: rsync ~/.cache/huggingface (see docs/operations.md). Images are 22-26 GB each.
# --dry-run prints the docker commands. Image selection follows the same policy as the recipes
# (release if validated -> digest -> nightly); DESKSIDE_IMAGE_CHANNEL overrides. Only images for THIS host's
# CPU architecture are saved -- pack on the same arch as the target.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../../recipes/lib/common.sh"
MODE="${1:-}"; DIR="${2:-}"; shift 2 || true
ARGS=(); for a in "$@"; do if [[ "$a" == --dry-run ]]; then DS_DRY_RUN=1; else ARGS+=("$a"); fi; done; set -- ${ARGS[@]+"${ARGS[@]}"}
case "${MODE}" in
  save)
    mkdir -p "${DIR}"; IDS=("$@"); [[ ${#IDS[@]} -gt 0 ]] || mapfile -t IDS < <(grep -vE '^#|^$' "${DS_LOCK}" | cut -d'|' -f1)
    for id in "${IDS[@]}"; do
      img="$(ds_image "${id}")" || { echo "skip ${id}" >&2; continue; }
      ds_pull "${img}"
      out="${DIR}/${id}.tar"
      ds_docker save -o "${out}" "${img}"
      [[ "${DS_DRY_RUN}" == 1 ]] || { echo "${img}" > "${DIR}/${id}.image"; sha256sum "${out}" >> "${DIR}/SHA256SUMS"; }
    done ;;
  load)
    [[ -d "${DIR}" ]] || { echo "no such dir ${DIR}" >&2; exit 3; }
    (cd "${DIR}" && [[ ! -f SHA256SUMS ]] || sha256sum -c SHA256SUMS)
    for t in "${DIR}"/*.tar; do ds_docker load -i "${t}"; done ;;
  *) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 3 ;;
esac
