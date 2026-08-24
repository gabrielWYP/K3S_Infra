#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
render="$(kubectl kustomize "${root}")"
workflow="${root}/../.github/workflows/deploy-movistar.yml"
storage="${root}/05-operations/restore-storage.template.yaml"
restore="${root}/05-operations/restore-job.template.yaml"

require_render() {
  grep -Fq -- "$1" <<<"${render}" || { echo "missing rendered contract: $1" >&2; exit 1; }
}

require_render "kind: Middleware"
require_render "name: reto-movistar-analyst-auth"
require_render "secret: reto-movistar-analyst-auth"
require_render "headerField: X-Forwarded-User"
require_render "removeHeader: true"
require_render 'Path(`/health`)'
require_render "priority: 200"

grep -Fq 'ANALYST_HTPASSWD:' "${workflow}"
grep -Fq 'ANALYST_HTPASSWD: ${{ secrets.ANALYST_HTPASSWD }}' "${workflow}"
grep -Fq 'kubectl create secret generic reto-movistar-analyst-auth' "${workflow}"
grep -Fq -- '--from-file=users=' "${workflow}"
grep -Fq 'test "${public_status}" = "401"' "${workflow}"

grep -Fq 'REPLACE_RESTORE_ID' "${storage}"
grep -Fq 'REPLACE_RESTORE_HOST_PATH' "${storage}"
grep -Fq 'persistentVolumeReclaimPolicy: Retain' "${storage}"
grep -Fq 'claimName: sonia-restore-target-REPLACE_RESTORE_ID' "${restore}"
grep -Fq 'image: REPLACE_BACKEND_IMAGE' "${restore}"
! grep -Fq ':bootstrap' "${restore}"
! grep -Fq '/mnt/tesis_data/movistar}' "${storage}"
! grep -Fq 'claimName: sonia-live' "${restore}"

echo "analyst auth and restore contract: PASS"
