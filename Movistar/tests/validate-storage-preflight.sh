#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="${root}/../.github/workflows/deploy-movistar.yml"
preflight="${root}/00-storage/storage-preflight-job.yaml"

test -f "${preflight}"
grep -Fq 'kind: Job' "${preflight}"
grep -Fq 'name: reto-movistar-storage-preflight' "${preflight}"
grep -Fq 'kubernetes.io/hostname: gabo-vm-arm' "${preflight}"
grep -Fq 'path: /mnt/tesis_data' "${preflight}"
grep -Fq 'type: DirectoryOrCreate' "${preflight}"
grep -Fq 'runAsUser: 0' "${preflight}"
grep -Fq -- '- CHOWN' "${preflight}"
grep -Fq 'mkdir -p /host/movistar /host/movistar-backups' "${preflight}"
grep -Fq 'chown 1001:1001 /host/movistar /host/movistar-backups' "${preflight}"
grep -Fq "stat -c '%u:%g:%a' /host/movistar" "${preflight}"
! grep -Fq 'privileged: true' "${preflight}"

grep -Fq 'job="reto-movistar-storage-preflight"' "${workflow}"
grep -Fq 'kubectl delete "job/${job}"' "${workflow}"
grep -Fq 'kubectl apply -f Movistar/00-storage/storage-preflight-job.yaml' "${workflow}"
grep -Fq 'kubectl wait --for=condition=complete' "${workflow}"

echo "storage preflight contract: PASS"
