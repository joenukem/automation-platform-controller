# Automation Platform Controller — Requirements for AAP 2.7 Product Parity

Status: DRAFT for review · Baseline verified 2026-08-16 · Owner: platform

Requirement IDs are stable (`CTL-xxx`). Priorities: **P0** (release-blocking),
**P1** (parity-blocking), **P2** (quality/scale). Every requirement names its
acceptance proof; per platform policy, proof means live behavior on a deployed
controller — never render-only checks, verify-on-existence, mocks, or canned
responses.

## 1. Scope

Build and release **Automation Platform controller 1.0**: a controller composed
from the live post-split upstream line (`ansible/awx` `devel` +
`django-ansible-base` + `dispatcherd` + `awx-plugins`) that

1. is drop-in compatible with the platform's existing integration surface
   (gateway, pcf-console, pool-manager `awx:` provider, lab-webapp driver), and
2. matches the AAP 2.7 automation-controller feature baseline for every feature
   the platform's courses and products exercise.

Out of scope: Red Hat trademarks, branding, subscription/entitlement features,
Insights/analytics upload to Red Hat, and the `ansible-ui` web UI (banned; the
console is `pcf-console`).

## 2. Composition and build

- **CTL-001 (P0)** — The controller is built from pinned commits of
  `ansible/awx` (`devel` line), `django-ansible-base`, `dispatcherd`,
  `awx_plugins.interfaces`, and `awx-plugins`. Every release records the exact
  upstream SHAs in the image labels and a `sources.lock` file in this repo.
  *Proof:* image inspect shows the labels; `sources.lock` matches them.
- **CTL-002 (P0)** — Images build on the prod1 `image-build` buildah pipeline
  with **no egress beyond the franken registry mirror and the pinned git
  mirrors**; a build must fail loudly if it attempts other network access.
  *Proof:* build log from a mirror-only network policy run.
- **CTL-003 (P0)** — Deliverables: `automation-platform/controller-web`,
  `controller-task`, and a combined migration job image, pushed to
  `franken-registry.example.com:5000` with semantic tags (`1.0.0-<sha>`);
  Helm values in `open-automation-platform-deploy` consume them.
  *Proof:* deployed on a throwaway ci-k3s-vm from those exact tags.
- **CTL-004 (P0)** — License hygiene: all composed sources are Apache-2.0 (or
  compatible); the release ships an SBOM (syft) and license manifest.
  *Proof:* SBOM artifact attached to the release report.

## 3. Compatibility contract (the platform must not notice the swap)

- **CTL-010 (P0)** — `/api/v2/` request/response compatibility for every
  endpoint the platform actually calls. The authoritative list is extracted
  from: pool-manager `provider_http.go`, lab-webapp `consoleDriverAgent.js` and
  embed proxy, pcf-console `shell/app/**` fetch paths, and all DO467/DO274
  lab `verify` scripts. That extraction is checked into
  `docs/api-surface.lock` and kept current by CI.
  *Proof:* a contract-test job replays the locked surface against the new
  controller and diffs status codes and response shapes.
- **CTL-011 (P0)** — Gateway integration unchanged: session auth via
  `awx-gateway` injected cookie, OIDC ROPC token flow, `/api/controller/v2`
  path prefix, CSRF behavior compatible with the embed console proxy.
  *Proof:* pcf-console login → launch → job output, driven through the
  lab-webapp embed, on a live session.
- **CTL-012 (P0)** — pool-manager `awx:` provider provisions and tears down a
  session (org, users, teams, credentials, project, inventories+hosts, job
  templates, workflow templates, EEs) against the new controller without code
  changes to the provider.
  *Proof:* a real `LabProvisioning` on the `ex467-aap-console` pool reaches
  Ready in ≤60s and deletes clean (see CTL-040).
- **CTL-013 (P1)** — Database migration from the running `awx 24.6.1` postgres
  is supported and rehearsed; alternatively a documented green-field cutover
  with fixture re-provisioning. The chosen path must be executed on a copy of
  the prod1 database before any production cutover.
  *Proof:* migration rehearsal report with row counts before/after.

## 4. Functional parity baseline (AAP 2.7 feature set the platform exercises)

Each item must behave as the AAP 2.7 documentation describes, proven through
the console and API, not assumed.

- **CTL-020 (P0)** — Organizations, users, teams; DAB-based RBAC with role
  definitions and object-level role assignments (`role_user_assignments`,
  `role_team_assignments` API used by the labs' verify scripts).
- **CTL-021 (P0)** — Credentials, credential types (custom types included),
  credential plugins via `awx-plugins`; machine/SCM/registry credentials.
- **CTL-022 (P0)** — Projects with git SCM sync (gitea), sync-on-launch,
  blocking sync (`projectSyncBlocking` provider behavior preserved).
- **CTL-023 (P0)** — Inventories: standard, smart, and **constructed** (with
  `source_vars`, input inventories, verbosity, cache timeout); hosts, groups,
  group/host/inventory variables; inventory sources with settled-status
  sync polling.
- **CTL-024 (P0)** — Job templates: surveys (all question types, validation
  enforced server-side at launch), `ask_*` prompt-on-launch fields,
  `extra_vars`, credentials, execution environments, instance/container group
  pinning, job slicing, forks, verbosity.
- **CTL-025 (P0)** — Workflow job templates: nodes, success/failure/always
  relations, **approval nodes** with timeout, workflow-level launch.
- **CTL-026 (P0)** — Execution environments: org-scoped EE records, image
  pull policy, per-template EE selection; jobs actually run in the selected
  image (proven by module availability differences, as ex467-09/s06 teach).
- **CTL-027 (P1)** — Schedules (rrule), notifications (webhook type at
  minimum: URL, method, SSL verification, success/error attachments, test
  send), activity stream.
- **CTL-028 (P1)** — Job-template **webhooks**: per-service key generation
  (`github` service at minimum), HMAC validation, `launch_type=webhook`
  recorded; 202 accept / 403 reject semantics.
- **CTL-029 (P1)** — Instance groups and container groups with pod-spec
  override; job placement recorded on the job.
- **CTL-030 (P1)** — Bearer tokens (`/api/v2/tokens/`), named URLs, bulk
  endpoints used by API-driven labs; Prometheus-compatible `/api/v2/metrics`
  consumable by awx-telemetry-agent.
- **CTL-031 (P2)** — Controller analytics/report endpoints the s07 lab reads;
  backup/restore-relevant export completeness (pagination guards).

## 5. Lifecycle correctness (the verified defects the frozen engine cannot fix)

These are the requirements our own incident evidence drives; each cites
`docs/parity-drivers.md`.

- **CTL-040 (P0) — no stranded resources on organization teardown.** Deleting
  an organization through the supported teardown path must leave zero
  session-created rows behind: inventories, projects, workflow job templates,
  job templates, schedules, notification templates. Whether the mechanism is
  cascade, subtree-delete API, or provider ordering, the observable contract
  is: after teardown, an unscoped list of each type shows no session remnants.
  (Driver: F18 — 118 orphaned inventories, 6 orphaned workflows on the frozen
  engine, because its org FKs are SET_NULL and teardown aborts on first 409.)
  *Proof:* leak-scan job that provisions and destroys 20 sessions in a loop
  and asserts zero orphans of every type.
- **CTL-041 (P0) — teardown is resumable, not abort-on-first-error.** A 409
  (`Resource is being used by running jobs`) on one object must cancel the
  blocking jobs and continue, or park with explicit status — never return
  early leaving a half-deleted org.
  *Proof:* teardown initiated while a job is running completes clean.
- **CTL-042 (P0) — no 4xx-as-success anywhere in the provisioning contract.**
  Every create in the provider path is confirmed by read-back; a 400 is a
  loud failure. (Driver: F17 — hub provisioning records rejected objects as
  created.) This requirement binds the provider and any controller-side bulk
  APIs equally.
  *Proof:* contract test injects a rejecting payload and asserts the
  provisioning fails visibly.
- **CTL-043 (P1) — scoped resolution.** The controller must make org-scoped
  queries cheap and canonical (`?organization=<id>` on every list the
  platform uses), so no platform component ever needs an unscoped
  first-result query. (Driver: `{{ inventory }}` resolving to dead sessions'
  objects.)
  *Proof:* driver template resolution updated to scoped queries passes the
  DO467 serial CI suite.
- **CTL-044 (P1) — launch wizard contract.** Launch endpoints must return
  structured validation errors the console can surface (survey validation,
  missing prompts), and the API must expose enough state for the console to
  render prompt/survey steps deterministically. (Driver: F9 history.)
  *Proof:* ex467-10 and ex467-16 green through the console wizard.

## 6. Scale and reliability (the platform's real load)

- **CTL-050 (P0)** — 10 concurrent lab sessions (this platform's stated CI
  parallelism) each provisioning, launching jobs, and tearing down, sustained
  for 2 hours, with: no 5xx from list endpoints, provisioning p95 ≤ 60s,
  list endpoints p95 ≤ 2s at 10k historical jobs.
  *Proof:* soak report; DO467 CI suite passing at MAX≥8 where it previously
  required MAX=3 (driver: concurrency fabricated failures on the frozen
  engine).
- **CTL-051 (P1)** — Multi-replica web with no sticky-session requirement
  beyond what the gateway already provides; dispatcherd-based task layer
  survives single-worker restart without losing queued jobs.
  *Proof:* kill-a-pod during the soak; zero lost jobs.
- **CTL-052 (P2)** — Job event delivery keeps console output live within 5s
  of task stdout under soak load (driver: output-settle sleeps the labs
  currently need).

## 7. Security

- **CTL-060 (P0)** — No default credentials; admin bootstrap via secret only;
  all platform access through gateway-issued identity. Session isolation:
  a session user must never see another session's objects (org-scoped RBAC
  enforced, superuser reserved for the platform).
- **CTL-061 (P1)** — Redacted logging: no secrets, tokens, or passwords in
  controller logs at default verbosity; webhook keys retrievable only via
  the authorized endpoint.

## 8. Release gates (definition of done for 1.0)

1. All P0 requirements proven live on a throwaway ci-k3s-vm deployment.
2. DO467 console-pool suite (the in-scope labs) green at MAX=3, and the three
   concurrency-victim labs green at MAX=8, against the new controller.
3. Leak-scan (CTL-040) reports zero orphans after 20 provision/destroy cycles.
4. Cutover rehearsal (CTL-013) executed against a prod1 database copy.
5. `docs/parity-drivers.md` updated: every driver either closed by evidence or
   explicitly carried as a known gap with a requirement ID.

## 9. Phasing

- **Phase 0 — spike (this proves feasibility, nothing ships):** build
  `ansible/awx` `devel` + DAB into images on the prod1 builder; boot against a
  scratch postgres; run one provision/launch/teardown cycle by hand.
- **Phase 1 — compatibility:** CTL-001..004, CTL-010..013 — the swap is
  invisible to gateway, console, provider, driver.
- **Phase 2 — parity:** CTL-020..031 proven feature by feature via the DO467
  suite (it is the platform's de-facto conformance suite).
- **Phase 3 — lifecycle + scale:** CTL-040..052, soak, cutover rehearsal,
  release 1.0.

## 10. Sources

- Upstream repositories: `ansible/awx` (devel), `ansible/django-ansible-base`,
  `ansible/dispatcherd`, `ansible/awx-plugins`, `ansible/awx_plugins.interfaces`.
- AAP 2.7 documentation set indexed in `open-automation-platform-deploy/docs/docs-sources.md`.
- Platform evidence: `lab-content/docs/AAP-PLATFORM-DEFECTS.md` (F9, F15, F17,
  F18), `lab-content/docs/LAB-PLATFORM-REFERENCE.md` (§3c concurrency),
  `lab-content/DO467/CI-SCOPE.md`.
