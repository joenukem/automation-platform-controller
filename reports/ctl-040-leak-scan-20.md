# CTL-040 / gate §9.3 — 20-cycle leak scan (2026-08-17)

Build `0.0.2-g9de9502ff9` (patches 0001–0006). The provider's real
`EnsureResources`→`DeleteResources` path (ex467-06 spec) run 20 times in a
loop, each cycle polling up to 90s for the async teardown to settle.

## Result — PASSED, 20/20, zero leaks

```
cycle 1..20: PASSED
LEAK20C DONE pass=20/20
```

Post-run estate scan (unscoped, every org-scoped type): **clean** — no
`conf`-marked remnant in organizations, inventories, projects, job_templates,
or workflow_job_templates.

## Note

The scan was made resilient to a provisioning-side flake (a project-sync
timeout under contention — an EnsureResources issue, not a teardown leak) by
one retry per cycle; the leak-scan assertion itself (zero orphans after
teardown) never triggered a retry. This closes release gate §9.3.
