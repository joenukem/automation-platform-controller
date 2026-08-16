# Parity Ledger — every AAP 2.7 controller feature, with a ruling

Status: NORMATIVE (CTL-070) · 2026-08-16

"Parity" is a defined claim only if every feature of the reference product has
an explicit ruling. This ledger enumerates the AAP 2.7 automation-controller
feature surface and rules on each. Releases must publish ledger deltas; a
feature without a ruling is a gap in this document, not silent scope.

**Rulings**
- **IN-1.0** — in scoped-parity 1.0 (the platform's courses/products exercise it; CTL section 4).
- **FULL** — required for full parity; scheduled on the full-parity track (see FULL-PARITY-PLAN.md) with its cluster ID.
- **GATEWAY** — in AAP 2.5+ this capability lives in the platform gateway, not the controller; delivered by `awx-gateway` (parity judged there, not here).
- **OUT** — excluded permanently, with justification (trademark, subscription, Red Hat SaaS coupling).

## 1. Identity, access, organizations

| Feature | Ruling | Notes |
|---|---|---|
| Organizations CRUD, galaxy credentials per org | IN-1.0 | plus ADR-0001 lifecycle semantics (improvement over reference) |
| Users, teams, org membership | IN-1.0 | |
| DAB RBAC: role definitions, user/team role assignments API | IN-1.0 | `role_user_assignments`/`role_team_assignments` used by lab verifies |
| Legacy `/roles/` compatibility API | FULL (F-RBAC) | older integrations; scoped surface uses DAB endpoints |
| Object-level granular permissions (all 30+ role types) | FULL (F-RBAC) | 1.0 needs the subset the suite exercises (execute/admin/use/read on templates, inventories, projects, credentials) |
| Platform authenticators: local, LDAP, SAML, OIDC, Azure AD, TACACS+, RADIUS, GitHub/Google social | GATEWAY | AAP 2.5+ moved authentication to the gateway; `awx-gateway` owns this ledger area |
| OAuth2 applications + tokens (`/applications/`, `/tokens/`) | IN-1.0 (tokens) / FULL (F-API) (applications) | labs mint personal access tokens; OAuth2 app registration is full-parity |
| Session limits, login/idle timeouts | GATEWAY | |
| Service accounts / service tokens (2.7) | FULL (F-RBAC) | gateway-issued; controller must honor |

## 2. Projects and content

| Feature | Ruling | Notes |
|---|---|---|
| Git projects, SCM credentials, sync, sync-on-launch, branch override | IN-1.0 | gitea-backed |
| Manual projects | FULL (F-CONTENT) | no platform use; trivial |
| Archive (tar/zip URL) projects | FULL (F-CONTENT) | |
| SVN projects | OUT | dead ecosystem weight; document as permanent exclusion |
| Insights projects (remediation plans) | OUT | Red Hat SaaS coupling |
| Collections/roles download during sync (requirements.yml, galaxy/hub creds) | IN-1.0 | against our hub |
| Signed-content verification during sync | FULL (F-CONTENT) | pairs with hub signing labs |
| Project revision tracking, playbook discovery | IN-1.0 | |

## 3. Inventory

| Feature | Ruling | Notes |
|---|---|---|
| Standard inventories, hosts, groups, variables at all three scopes | IN-1.0 | |
| Smart inventories (`host_filter`) | IN-1.0 | console renders; verify exercises |
| Constructed inventories (source_vars, input inventories, limit, cache) | IN-1.0 | s03 |
| Inventory sources: SCM-based | IN-1.0 | |
| Inventory source plugins: ec2, azure_rm, gce, vmware, openstack, satellite, controller, terraform (2.6+), OpenShift Virtualization (2.6+) | FULL (F-INV) | one plugin cluster; enable per-plugin as course demand appears; creds are the hard part |
| Fact caching (per-host ansible_facts, cache timeout) | FULL (F-EXEC) | |
| Bulk host create/delete API | IN-1.0 | provider uses bulk paths for speed |
| Host metrics / indirect node counting (2.5+) | OUT | subscription counting machinery |
| Provisioning callbacks (`/job_templates/N/callback/`) | FULL (F-EXEC) | classic PXE/cloud-init pattern; cheap |

## 4. Execution resources

| Feature | Ruling | Notes |
|---|---|---|
| Job templates: full prompt-on-launch matrix (`ask_*`), extra_vars, precedence | IN-1.0 | |
| Surveys: all question types, validation, `$encrypted$` defaults | IN-1.0 | |
| Credentials on templates (multi, prompt), credential types (custom) | IN-1.0 | s02 |
| Credential plugins (external secrets): HashiCorp Vault KV/SSH (incl. 2.7 OIDC auth), CyberArk AIM/Conjur, Azure Key Vault, AWS Secrets Manager, Thycotic, Centrify, GitHub App (2.6+) | FULL (F-CRED) | via `awx-plugins`; Vault KV first (course-relevant), rest per demand |
| Execution environments: registry creds, pull policy, per-template/org/global selection | IN-1.0 | |
| Job slicing, forks, verbosity, timeouts, diff mode | IN-1.0 | s06 |
| Instance groups, container groups, pod-spec override, per-template pinning | IN-1.0 | pod execution is the only backend (ADR pending, D-3) |
| Labels | IN-1.0 | s08 estate uses labels |
| Workflow job templates: nodes, all edge types, convergence (any/all), nested workflows | IN-1.0 (nested: FULL, F-EXEC) | |
| Workflow approval nodes (timeout, approve/deny RBAC) | IN-1.0 | |
| Workflow-level prompts/surveys propagating to nodes | FULL (F-EXEC) | subtle semantics; document precedence exactly |
| Schedules: rrule, multi-rule complex schedules (2.4+), prompts on schedules | IN-1.0 (basic rrule) / FULL (F-EXEC) (complex + prompted) | |
| Notification templates: webhook | IN-1.0 | |
| Notification types: email, Slack, PagerDuty, Grafana, Twilio, Mattermost, Rocket.Chat, IRC | FULL (F-NOTIFY) | mechanical breadth; one shared framework |
| Job-template webhooks: GitHub, GitLab services; Bitbucket (2.5+) | IN-1.0 (github) / FULL (F-NOTIFY) (gitlab, bitbucket) | |
| Ad hoc commands (module allowlist, RBAC) | IN-1.0 | console run-command uses it |
| System jobs / cleanup (activity stream, job history retention) | FULL (F-OPS) | needed before any long-lived deployment |

## 5. Execution engine and topology

| Feature | Ruling | Notes |
|---|---|---|
| Container-based job isolation (EE pods) | IN-1.0 | the only backend |
| Automation mesh: receptor, execution/hop nodes, node management UI/API, mesh visualizer, work signing | FULL (F-MESH) | the single largest full-parity item; deliberately absent from 1.0 (D-3) |
| Instance management API (`/instances/`, health checks, capacity adjustment, node install bundles) | FULL (F-MESH) | |
| Capacity algorithm (forks/mem/cpu-based), impact accounting, per-IG max-forks/max-jobs | IN-1.0 (basic) / FULL (F-SCALE) (full policy surface) | CTL-050 defines our floor |
| Task dependency graph (project update → inventory update → job ordering) | IN-1.0 | correctness-critical (D-2) |
| Fact cache injection into runs | FULL (F-EXEC) | with fact caching above |
| Remote archive/artifact handling (`set_stats`, workflow artifact passing) | IN-1.0 | workflow labs rely on artifacts |

## 6. API and integration surface

| Feature | Ruling | Notes |
|---|---|---|
| `/api/v2` CRUD on the scoped surface (api-surface.lock) | IN-1.0 | CTL-010 |
| Full Django-style filtering: `__lookups`, `chain__`, `not__`, `__search`, `or__` | FULL (F-API) | 1.0 guarantees the lock's filters; full grammar is F-API |
| Named URLs | FULL (F-API) | cheap |
| Copy endpoints (`/copy/` on templates, inventories, projects, credentials) | FULL (F-API) | |
| Bulk API: bulk job launch, bulk host ops | IN-1.0 (hosts) / FULL (F-API) (bulk launch) | |
| Activity stream on every mutation, with actor | IN-1.0 (mutations we exercise) / FULL (F-API) (complete coverage audit) | |
| `/api/v2/metrics` (Prometheus) | IN-1.0 | telemetry-agent scrape |
| OpenAPI/schema endpoint | FULL (F-API) | also serves our own contract tests |
| `awx` CLI compatibility | FULL (F-CLI) | export/import workflows depend on it |
| `ansible.controller` / `ansible.platform` collection compatibility | FULL (F-CLI) | s08-class CaC labs are the consumer; high-value |
| Event streams to EDA (2.5+ gateway event streams) | GATEWAY | eda-server + gateway own it |
| MCP server surface (2.7 tech preview) | OUT (revisit) | tech preview; revisit when stable upstream |

## 7. Operations

| Feature | Ruling | Notes |
|---|---|---|
| Settings API (the full `/settings/` sprawl) | FULL (F-OPS) | 1.0 ships fixed sane config + the handful the platform tunes |
| Logging aggregators (Splunk, Loki, Logstash, external syslog) | FULL (F-OPS) | structured stdout first (D-10); aggregators after |
| Backup/restore procedure | IN-1.0 (documented, rehearsed) | labs 16/19 teach the concept against our estate |
| HA: multi-web, task-manager failover, dispatcher lease recovery | IN-1.0 | CTL-051, D-2 |
| Upgrade/migration tooling | IN-1.0 | CTL-013 |
| Analytics gathering/shipping to Automation Analytics (console.redhat.com) | OUT | Red Hat SaaS |
| Subscription/entitlement enforcement, license counting | OUT | trademark/subscription machinery |
| Automation dashboard (2.7 tech preview) | OUT (revisit) | platform has its own telemetry consoles |
| Policy as code (OPA integration, 2.6+ preview) | OUT (revisit) | platform's policy repo covers the need |
| Custom branding/login | GATEWAY | console/gateway concern |

## Ledger accounting (2026-08-16)

- IN-1.0: 38 features (incl. split rows' 1.0 halves)
- FULL: 34 features across 9 clusters — F-MESH, F-RBAC, F-CRED, F-INV, F-EXEC, F-NOTIFY, F-API, F-CLI, F-OPS, F-CONTENT, F-SCALE
- GATEWAY: 6 · OUT: 8 (3 marked revisit)

Every OUT ruling is reviewable; nothing is silently absent. The FULL clusters
are sequenced and costed in `FULL-PARITY-PLAN.md`.
