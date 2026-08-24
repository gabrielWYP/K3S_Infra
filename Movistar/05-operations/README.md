# SON-IA local storage operations

The live 5Gi and backup 10Gi volumes are retained static local PVs on `gabo-vm-arm`.
Backups run daily at 02:00 UTC and delete only `backup-*` directories older than 14 days.
This meets RPO 24h/RTO 4h only while the node and disk survive; off-node replication is a
production follow-up.

Before rollout, create both host directories, assign UID/GID 1001, and verify the node label.
Apply the overlay, then confirm both PVCs are Bound and `/ready` is 200. Backend uses one
replica and `Recreate`, so expect brief rollout downtime; front topology is unchanged.

## Restore drill (manual and non-destructive)

1. Choose a checksummed `backup-*` directory and stop run creation.
2. Provision a new retained local PV/PVC named `sonia-restore-target` on a fresh host path;
   never bind it to `/mnt/tesis_data/movistar`.
3. Copy `restore-job.template.yaml`, replace only `REPLACE_BACKUP_NAME`, apply it, and wait
   for success. The job refuses a reused destination and never mounts the live PVC.
4. Start a temporary backend against the restored subdirectory and require `/ready` plus
   dataset, package, history, and review reads to match the source manifest.
5. Promotion is explicit: scale backend to zero, retain/export the old PVC, update the live
   claim to the verified replacement, then scale to one. Never overwrite live storage.

## K3S acceptance run (task 5.4)

With the released image and authenticated ingress: upload the six canonical CSVs, answer all
questions, create/start one run whose Judge fixture produces exactly one retry, and require a
terminal package with eight ordered history entries. Restart the backend between committed
phases and prove polling resumes without duplicated steps. Trigger a backup Job from the
CronJob, perform the restore drill, then decide the exact package and prove that the decision
survives another restart. Verify all recommendations remain read-only and no external system
was contacted. Capture run/package IDs, pod UIDs, manifest digests, events, and timestamps;
static render or an unreachable API does not complete task 5.4.
