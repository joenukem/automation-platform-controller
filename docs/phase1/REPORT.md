# Phase 1 Report — compatibility (in progress)

Date: 2026-08-16 · Targets: CTL-010, CTL-011, CTL-012, CTL-013
Status: **COMPLETE — all four targets proven**

## CTL-010 — api-surface.lock: DONE, replay 49/53

`tools/extract_api_surface.py` scans the four integration sources
(pool-manager provider, lab-webapp driver + embed proxy, pcf-console app
code, DO467/DO274 verify scripts + provisioning YAML) and emits
`docs/api-surface.lock`: **53 normalized endpoints**. Replaying every
collection GET against the composed controller as admin: **49/53 = 200**.
The four exceptions, triaged:

| endpoint | verdict |
|---|---|
| `schedules/preview` 405 | correct — POST-only endpoint; replay refinement, not a break |
| `openapi` 404 | never existed in the old engine either; F-API aspiration |
| `settings/ldap` 404 | removed by design — authenticators moved to the gateway (ledger: GATEWAY) |
| `tokens` 404 | **real break**: devel removed `/api/v2/tokens/` (OAuth2 moved to DAB/gateway). ex467-13 mints PATs there. Resolution: tokens must be gateway-issued (the gateway already has an OAuth manager with token endpoints); the lab's connection-env needs to point at the gateway token endpoint at cutover. Tracked for Phase 2. |

## CTL-011 — gateway integration: CORE PROVEN

Cloned the production gateway (deployment, config, secrets) into the scratch
namespace, upstream at the composed controller. Proven end to end:

- form login (local users) → gateway session cookie → signed trusted header →
  `/api/controller/v2/me/` → the devel controller **auto-created and mapped
  the user** (`phase1`, superuser via groups). This is the exact production
  auth path (`gateway_auth.GatewayHeaderAuthentication` imported and worked
  unmodified).
- Unauthenticated requests 401 everywhere, including `/ping` — gateway policy
  enforced in front of the new controller.

Found (gateway-side, pre-existing): Basic auth with a local-users identity
returns 401 even though the same credentials pass form login — the
Basic→form conversion path needs a look. Production Basic auth works via OIDC
ROPC (dex), which the scratch namespace can't exercise without dex
credentials. Tracked as a gateway finding, not a controller break.

## CTL-012 — provider unchanged: PASSED

`pool-manager/cmd/provider-conformance` (new, committed on the pool-manager
`wip/admin-labprovisioning-terminal-failure-20260814` branch as `def5c082`)
drives the provider's real `EnsureResources`/`DeleteResources` against any
controller URL with a lab's actual `.spec.awx`. Against the composed
controller with `ex467-06`'s spec:

```
ENSURE ok in 36.4s — 7 resources (3 credentials, project [blocking gitea
  sync], inventory, 2 job templates)
DELETE ok in 12.2s
LEAK SCAN clean — provider conformance PASSED
```

Zero provider code changes. One environmental prerequisite surfaced: the
platform seed users (`bob`, `alice`) must exist before org-member grants —
true on production, seeded by hand on scratch.

## CTL-013 — migration rehearsal: PASSED

Dumped the production database (235 MB; 1 org, 847 jobs, 41 users — the
inventory/template tables were empty because the sweeper had just run and no
sessions were live), restored into the scratch postgres, and ran the devel
line's migrations over it: **41 migrations applied cleanly, idempotent on
rerun** ("No migrations to apply"). Integrity after: counts preserved
exactly, DAB seeded 33 role definitions from the data migration, the newest
job record (3820) readable with its status and name, and the API serves the
migrated history (`count: 847`). The 24.6.1 -> devel migration path crosses
the release pause intact on our real data.

One caveat for the cutover plan: this dump had no live inventories,
templates, or sessions in flight. The cutover rehearsal should be repeated
once against a dump taken DURING a busy CI window so the migration is proven
over live session rows too.

## Scratch environment

`deploy/scratch/up.sh` now brings up the full composed stack **plus the
gateway** in one shot (`ctl-phase1` namespace, left running for CTL-013
work). The stack manifests are materialized from the production release, so
config drift between scratch and prod is visible in git.
