# CTL-051 — dispatcher survival (2026-08-17)

Build `0.0.2-g9de9502ff9`. Test: a job in flight when its task (dispatcher)
pod dies must not be lost — it either completes on the recovered worker or
reaches a visible terminal state, never stuck.

## Method

1. Launched job 4072 (org/inventory/project-sync/JT via the provider path).
2. With the job `pending` (queued in the dispatcher), **force-deleted the
   `awx-controller-task` pod** (`--grace-period=0 --force`).
3. Watched the job through the new pod's startup.

## Result — PASSED

```
status before kill: pending
task pod force-deleted; deployment rolled out
t+10..40s: pending   (queued, waiting for the new dispatcher)
t+50s:     running    (new task pod picked it up)
t+60s:     successful
```

The queued job survived the dispatcher's violent death and completed on the
recovered worker. Zero jobs lost — the dispatcherd/postgres queue persists
across a single-worker restart exactly as CTL-051 requires.
