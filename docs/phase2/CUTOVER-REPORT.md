# Phase 2 — native prod1 cutover and live conformance

Date: 2026-08-16 · Authorized: prod1 designated as the controller test bed
(other tenant: an unrelated CI pool, verified undisturbed throughout).

## What was cut over

prod1's `automation-platform` namespace now runs the candidate:

- `awx-controller-web` (3 replicas) and `awx-controller-task` swapped from
  `ansible/awx:24.6.1` to
  `automation-platform/controller:0.0.1-phase0` (receptor sidecar and EE
  images unchanged — they are allowed artifacts).
- `awx-controller-settings` patched with the two proven drifts (DABRedisCache;
  OAuth2 auth class removed). Original CM, deployment manifests, and a
  pre-cutover `pg_dump` are staged as rollback artifacts.
- All 41 devel migrations applied over the live production database,
  idempotent on rerun. `/api/v2/ping/` → `25.0.0.dev0`.

## The tokens break, met in production form

pool-manager authenticated to the controller with an **OAuth2 token** —
machinery devel removed. Basic auth support already existed in the provider
config; the provider secret now carries `awx-username`/`awx-password` (fresh
admin credential) with the old token preserved for rollback. This retires the
Phase-1 "tokens" carried item for the *provider*; the ex467-13 lab's PAT flow
remains a Phase 2 work item (gateway-issued tokens).

## Live conformance (real platform, real sessions, serial CI)

| proof | result |
|---|---|
| provider-conformance harness vs live controller | ENSURE 7 resources / DELETE / leak-scan clean |
| first real `LabProvisioning` | Ready in ~30s |
| ex467-06 (inventories, groups, vars) | **PASS** |
| ex467-08 (project from git) | **PASS** |
| ex467-17 (troubleshoot controller job — seeded broken credential, console diagnosis, graded verify) | **PASS** |
| gateway ROPC (Keycloak user → `/api/v2/…` via ap-console) | 200 |

The unrelated tenant pool (`ansible-navigator-alma10`) provisioned sessions
continuously during the window, unaffected.

## Failure investigated to ground truth

ex467-17 initially failed 3× with an anonymous `curl: (22) … 401` from its
seed script. Chased through: gateway logs (both gateways — the 401s were at
`oap-automation-platform-gateway`, which fronts `ap-console.pipefail.dev`),
credential-flow reproductions (Keycloak ROPC, pre-existing controller user —
all 200), and content-pipeline archaeology. Outcome:

1. Root cause (RCA'd in lab-webapp, fixed at source as `e1036ee777`): the
   webapp's local provisioning fallback fired on essentially every warm-pool
   session — `waitForLabProvisioningAllocation` returns at phase `Allocated`
   (seconds), the code treated "not Ready" as "operator failed", and the
   fallback DUPLICATED the operator's work, running the lab's `setup.sh` a
   second time seconds later with the webapp's own (stale) content copy. That
   explains the anonymous 401s, the `connection-env.sh` permission races, and
   why instrumented provisioning changes seemed not to take effect. The fix
   waits `LAB_PROVISIONING_READY_GRACE_SECONDS` (default 180) before the
   fallback may engage; deployed to prod1 as web-image overlay
   `lab-webapp:diag3-grace-e1036ee`. Not a controller regression.
2. The seed now reports `HTTP <code> from: <url>` instead of curl's anonymous
   exit 22 (lab-content `53ca469d6`) — the next such failure names itself.
3. **Content-pipeline finding worth keeping:** the production webapp's
   provisioning specs come from its `/app/lab-content` copy, refreshed only by
   `deploy_lab_content.sh` (or image rebuild) — `FORCE_CONTENT_FETCH` does not
   refresh them; and pool-manager's own copy comes from a baked image synced
   at pod start. A provisioning edit is live only after a content deploy.

## Standing consequence

The DO467 suite — the platform's conformance spec — now runs against the
candidate controller **by default** on every CI invocation. Phase 2's
feature-by-feature parity work (CTL-020..031) proceeds by driving the
remaining labs green in this configuration.

## Rollback (unused, staged)

Scale web/task to 0 → restore `awx-pre-cutover.dump` → revert images + CM
from the staged backups → restore `awx-token` in the provider secret →
restart pool-manager. All artifacts in the session scratchpad and on the
postgres pod.
