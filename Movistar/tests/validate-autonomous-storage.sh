#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
render="$(kubectl kustomize "${root}")"
backup="${root}/05-operations/backup-cronjob.yaml"
restore="${root}/05-operations/restore-job.template.yaml"

require() { grep -Fq -- "$1" <<<"${render}" || { echo "missing: $1" >&2; exit 1; }; }
count() { test "$(grep -Fc -- "$1" <<<"${render}")" = "$2" || { echo "bad count: $1" >&2; exit 1; }; }

count "kind: Deployment" 2
count "name: reto-movistar-front" 4
require "name: sonia-live"
require "name: sonia-backups"
require "storageClassName: local-storage"
require "persistentVolumeReclaimPolicy: Retain"
require "storage: 5Gi"
require "storage: 10Gi"
require "path: /mnt/tesis_data/movistar"
require "path: /mnt/tesis_data/movistar-backups"
require "kubernetes.io/hostname"
require "values:"
require "- gabo-vm-arm"
require "type: Recreate"
require "runAsUser: 1001"
require "runAsGroup: 1001"
require "fsGroup: 1001"
require "mountPath: /var/lib/sonia"
require "path: /ready"
require "kind: CronJob"
require "concurrencyPolicy: Forbid"
require "schedule: 0 2 * * *"
require "name: reto-movistar-backup"
require "mountPath: /var/backups/sonia"

grep -Fq 'StorageHardener(Path("/var/lib/sonia"))' "${restore}"
! grep -Fq '/unused-live' "${restore}"
grep -Fq 'case "${BACKUP_NAME}" in backup-*)' "${restore}"
grep -Fq 'destination="/restore/restored-${BACKUP_NAME}"' "${restore}"
grep -Fq 'test ! -e "${destination}"' "${restore}"
grep -Fq '{name: backups, mountPath: /backups, readOnly: true}' "${restore}"
grep -Fq 'persistentVolumeClaim: {claimName: sonia-restore-target-REPLACE_RESTORE_ID}' "${restore}"
! grep -Fq 'claimName: sonia-live' "${restore}"
grep -Fq 'test "$(realpath /var/backups/sonia)" = /var/backups/sonia' "${backup}"
grep -Fq -- "-mindepth 1 -maxdepth 1 -type d -name 'backup-*' -mtime +13" "${backup}"
test -f "${root}/05-operations/README.md"
echo "autonomous storage contract: PASS"
