#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="${root}/.github/workflows/deploy-movistar.yml"

ghcr_step="$(sed -n '/- name: Reconcile GHCR pull secret/,/- name: Reconcile OpenCode Go secret/p' "${workflow}")"
opencode_step="$(sed -n '/- name: Reconcile OpenCode Go secret/,/- name: Apply immutable release/p' "${workflow}")"

grep -Fq 'GHCR_PULL_TOKEN: ${{ secrets.GHCR_PULL_TOKEN }}' <<<"${ghcr_step}"
grep -Fq 'kubectl create secret generic ghcr-pull-secret' <<<"${ghcr_step}"
! grep -Fq 'OPENCODE_KEY' <<<"${ghcr_step}"

grep -Fq 'if [ -z "${OPENCODE_KEY:-}" ]; then' <<<"${opencode_step}"
grep -Fq 'kubectl delete secret reto-movistar-opencode' <<<"${opencode_step}"
grep -Fq -- '--ignore-not-found' <<<"${opencode_step}"
grep -Fq 'kubectl create secret generic reto-movistar-opencode' <<<"${opencode_step}"

echo "deployment secret contract: PASS"
