# Full-Parity Design — the engineering design and proof discipline for genuine AAP 2.7 parity

Status: **AUDIT COMPLETE (7/7 strands)** · 2026-08-17 ·
Companion to `PARITY-LEDGER.md` (what parity means), `FULL-PARITY-PLAN.md` (the
costed sequence), and `DESIGN-AGENDA.md` (the owned decisions D-1..D-12). This
document adds the layer those three do not: the **code-grounded engineering
design** for closing the FULL clusters, verified against the pinned upstream tree,
and the **proof discipline** that makes "full parity" a demonstrated claim rather
than an asserted one.

## 0. The headline, up front

A code-grounded audit of every FULL cluster against the pinned upstream trees
(`upstream/awx` @ `3fea070`, `upstream/awx-plugins`, `upstream/django-ansible-base`,
`upstream/dispatcherd`, `upstream/awx_plugins.interfaces`) reaches one dominant
conclusion:

> **Full AAP 2.7 parity is overwhelmingly a *prove-what-we-inherit* effort, not a
> *write-a-controller* effort. Genuine net-new controller code is a small,
> bounded set (~2–3 focused weeks); the real cost — the bulk of the ~26–32
> engineer-weeks in `FULL-PARITY-PLAN.md` — is conformance-test authoring and
> live-counterpart *test realism*, plus the standing stewardship tax.**

Every "FULL" feature was found present and wired in the composed upstream stack,
with **three exceptions** that are the genuine beyond-upstream frontier (§5):
(1) a **branding-neutral product-name gate** patch — the single highest-leverage
item, because upstream *disables* the entire external-secrets and "supported"
cloud surface unless the runtime reports a non-`AWX` product name; (2) a
**pod-native backup/restore** procedure — the one operational artifact upstream
delivers only via awx-operator, which this pod-only fork does not inherit; and
(3) **persisting the mesh CA + work-signing keypair** — a cheap seam-preservation
fix that keeps automation mesh an *additive* future rather than a rewrite. A
fourth, conditional item is wiring DAB's `ServiceTokenAuthentication` if
controller↔hub/EDA service tokens are required (else marked inert).

This reframes the answer to "what code gaps get written": **not a controller — a
proof harness, a live-counterpart test estate, and roughly three small patches.**

The cross-cutting delta audit (what AAP 2.7 has that awx `devel` lacks) puts a
number on it — the full AAP 2.7 controller-parity surface splits as:

| Bucket | ~Share | Meaning |
|---|---|---|
| **INHERITED** from upstream (enable + conformance-test, ~0 feature code) | **~70–75%** | inventory + credential plugins (incl. Vault OIDC, GitHub App), **OPA policy-as-code**, notifications, webhooks (incl. Bitbucket DC), signed content, multi-rule schedules, mesh core, awxkit, DAB RBAC |
| **GATEWAY / OTHER-SERVICE** (not the controller's job) | **~15%** | auth/authenticators, token mint, SSO, session limits, branding, EDA event streams, `ansible.platform`, automation dashboard, MCP server, portal |
| **OUT** — SaaS / subscription / trademark | **~8–10%** | shipping analytics to console.redhat.com, RHSM/candlepin entitlement enforcement, certified-content entitlement |
| **Genuine net-new controller code** | **~2–5%** | and even this is integration glue + test harnesses + the fork's own improvements — almost none is reimplementing an AAP controller *feature* |

Independently verified against the pinned source: the controller-owned OAuth2
provider is **removed** (migration `0204` deletes the models); `AUTHENTICATION_BACKENDS`
is awx-model-only (authenticators live in the gateway) — confirming the GATEWAY
bucket by design, not omission.

## 1. The premise that reshapes the whole effort

The controller **is** the upstream `ansible/awx` `devel` line (pinned in
`sources.lock`) plus a small `patches/` queue. Red Hat's AAP 2.7 controller is
the *same* line plus downstream product integration. Therefore **most of the
"AAP 2.7 controller feature surface" is already in the box** — inherited, not
written. Verified example: the entire notification-backend set
(`awx/main/notifications/{email,slack,pagerduty,grafana,irc,mattermost,rocketchat,twilio,awssns,webhook}_backend.py`),
all external-secret credential plugins (`awx-plugins/src/awx_plugins/credentials/`),
all cloud inventory injectors (`awx-plugins/src/awx_plugins/inventory/plugins.py`),
the API framework (`awx/api/generics.py`, filter grammar now in DAB), the full
`/instances/` mesh API, and the legacy `/roles/` compat shim all ship today.

The corollary — and the most important thing this document does — is to sort each
feature into one of three buckets **with a cited upstream path**, because the
failure mode of parity projects is counting inherited code as delivered work, or
shipping a feature that "exists" but was never proven to behave like the reference.

### 1.1 The three-bucket taxonomy

| Bucket | Definition | Parity work | Danger |
|---|---|---|---|
| **INHERITED** | Present & functional in pinned upstream as-is. | A **conformance test** that pins behavior. | Claiming it "for free" — regressions on rebase go unseen. |
| **ENABLEMENT-GAP** | Code exists upstream but is off / unwired / unconfigured / untested in our build. | Config + wiring + a **live** test. | "It's in the code" ≠ it works in our deployment. |
| **NET-NEW** | Genuinely absent from `awx` + `awx-plugins` + DAB. The real *beyond-upstream* frontier. | New controller code + design + test. | Under-scoping (rarely zero) or over-scoping (writing what's inherited). |

## 2. What "genuine" means — the proof discipline (anti-fake-parity rules)

Genuine parity is a claim about **behavior**, provable without running Red Hat's
product (the oracle-weakness risk). These rules are normative; a feature is not
"parity" until it clears them.

1. **No verify-on-existence.** A feature is not done because the code is present
   or the endpoint returns 200 — only when a test drives the *documented behavior*
   and asserts the *documented result*.
2. **Name the oracle before building**, strongest to weakest:
   - **Executable oracle** — a public suite we run: the `ansible.controller`/`awx.awx`
     collection integration targets (45 of them), awxkit's tests, awx's own API
     tests. Strongest; use wherever it exists.
   - **Documentary oracle** — an AAP 2.7 docs table → a **table-driven test**
     (variable/survey/prompt precedence is the canonical case).
   - **Live-counterpart oracle** — for integrations (creds, notifications, inventory,
     log aggregators), a **real service** the feature talks to. *A plugin without a
     live test is not shipped.*
   - **Interpreted** — where docs are ambiguous and no public test exists, flag the
     ledger row `interpreted`, write the assumption down; never a silent guess.
3. **Test-or-mark-inert for the settings sprawl.** Every `/settings/` key has a
   behavior test **or** is explicitly recorded *accepted-and-inert* with a
   justification class. A CI meta-test iterates the setting registry and fails on
   any key not present in the ledger. Silent inert settings are how fake parity ships.
4. **The ledger is the scoreboard.** A cluster is done when every row flips to
   *shipped-with-test*; each release publishes the delta as `N/M rows, K interpreted`.
5. **Rebase-durability.** Because we track upstream, every conformance test is also
   a **regression tripwire** for the monthly rebase (CTL-072) — inherited features
   especially, since they are exactly what a silent upstream change can break.

## 3. Shared engineering seams (design once, reuse across clusters)

The three "breadth" clusters (F-CRED, F-NOTIFY, F-INV) are "add another backend"
work — and the seams **already exist upstream**; adopt them as-is rather than
inventing abstractions.

- **External-secret lookup seam** — a `CredentialPlugin` NamedTuple
  (`awx-plugins/.../credentials/plugin.py`: `name`, `inputs{fields,metadata}`,
  `backend(**kwargs)->str`), registered as an `awx_plugins.credentials` entry
  point, discovered at `awx/main/models/credential.py:688`. Implement against the
  public `awx_plugins.interfaces` shims, never awx internals. Adding a plugin =
  one module + one entry point + one SDK pin + one unit test.
- **Notification-backend seam** — a Django `EmailBackend` subclass mixing
  `CustomNotificationBase` (`init_parameters`, `recipient_parameter`,
  `default_messages`, `send_messages()->int`), registered in
  `NOTIFICATION_TYPES` (`awx/main/models/notifications.py:42`). `password`-typed
  params auto-encrypt; messages render through a `jinja2.sandbox`. Adding a type =
  one file + one registry line + one sink test.
- **Inventory-source injector seam** — a `PluginFileInjector` subclass +
  a paired `ManagedCredentialType`, both discovered by entry point
  (`awx_plugins.inventory` / `awx_plugins.managed_credentials[.supported]`);
  the controller loads them at `awx/main/models/inventory.py:932`. Cloud logic
  lives in EE collections, not the controller — the controller side is the
  injector env/files + the credential type.

Each seam gets **one live-test harness** (a deployable counterpart + a table-driven
per-backend conformance job), so backend N is config + a fixture, not new scaffolding.

## 4. Per-cluster audit — inherited / enablement / net-new

Effort is in focused **engineer-days** unless noted. "net-new" days are *code*;
"enablement" days are wiring+config+live-test; the large residual is
conformance-test authoring. Every path was opened in the pinned tree.

### 4.1 F-API + F-CLI  — net-new ≈ 0

All INHERITED: filter grammar `__search/chain__/or__/not__/__lookups`
(now in **DAB** `rest_filters/…/field_lookup_backend.py`), named URLs
(`utils/named_url_graph.py`), copy endpoints (`generics.py:873 CopyAPIView`, 7
registrations), **bulk job launch + bulk host ops** (`api/views/bulk.py` — the
ledger over-scoped launch as FULL; it is present), activity stream
(`main/signals.py`, ~30-model mapping), OpenAPI schema (now **drf-spectacular**
via DAB, fork-enhanced in `api/schema.py`), and awxkit (`awxkit/`).
**One ENABLEMENT item carries the cluster:** build & run the `ansible.controller`
collection (rename path already exists: `awx_collection/Makefile` +
`tools/roles/template_galaxy/`) against a live controller — its **45 integration
targets** are the definitive oracle and the only place fork-introduced schema
divergence can surface. Ledger fix: **split `ansible.controller` (buildable here)
from `ansible.platform` (gateway)**. Effort ≈ **26–30 enablement/test-days, 0 net-new.**

### 4.2 F-EXEC + F-CONTENT  — net-new = 0

100% INHERITED, verified on a **clean working tree** (genuine upstream, not
fork-local): workflow-node prompt **precedence** (`models/workflow.py:299`,
`mixins.py:308`), nested-workflow artifact seeding (`workflow.py:743`), complex
multi-rule + prompted schedules (`models/schedules.py`), fact caching + injection
(`tasks/facts.py`, `tasks/jobs.py:1312`), provisioning callbacks
(`api/views/__init__.py:3053`), manual/archive projects (`models/projects.py`),
signed-content validation credential (`projects.py:291`), DAG ordering, `set_stats`
artifacts. **The design centerpiece is the precedence test matrix** — three tables
(standalone JT launch; workflow-node→JT with the "WFJT-extra_vars-override-everything"
special case; node→nested-WFJT), each documented rule becoming one assertion; the
nested-workflow artifact path is the riskiest (subtlest + historically divergent)
and already has a **live** oracle to grow. Three ENABLEMENT-GAPs, all test-realism:
fact-cache pod-mount round-trip, signing keyring+hub counterpart, callback
inventory-update. Effort ≈ **27.5 days (0 net-new, ~8 enablement, ~19.5 conformance).**

### 4.3 F-CRED  — net-new ≈ 2–3 days (the product-name gate)

**Every** AAP 2.7 external-secret plugin is INHERITED and wired: Vault KV & SSH,
**Vault KV/SSH OIDC (the 2.7 workload-identity mode)**, Conjur, CyberArk AIM,
Azure KV, AWS Secrets Manager, Centrify, Delinea DSV & Secret Server, GitHub App
— all in `awx-plugins/.../credentials/`, SDKs in the requirements lock, discovered
at `credential.py:688`. The 2.7 Vault-OIDC flow — the leading net-new *candidate*
— is **inherited** end to end (`populate_workload_identity_tokens` →
`workload_identity_auth` → self-token revoke; gated by
`FEATURE_OIDC_WORKLOAD_IDENTITY_ENABLED`); its JWT *issuer* is the **gateway**
(judged there). Custom credential types, input sources, `$encrypted$`, and the
OIDC-aware `/test/` endpoints are all INHERITED. **The one genuine net-new item:
the branding-neutral product-name gate** (§5.1). Effort ≈ **24–37 days, of which
~2–3 are net-new; ~90% is live test-infra** (self-host Vault/Conjur/Secret
Server/LocalStack; recorded-contract doubles for proprietary AIM/Centrify/DSV/Azure/GitHub-App).

### 4.4 F-NOTIFY + F-INV  — net-new = 0 (shares the §5.1 gate)

**~29 INHERITED, 1 ENABLEMENT-GAP, 0 NET-NEW.** All 10 notification backends +
custom-message Jinja templating + per-event routing, and **all three** webhook
receivers (GitHub/GitLab/**Bitbucket DC 2.5+**) with status post-back, are present.
All cloud inventory injectors (ec2/azure_rm/gce/vmware/vmware_esxi/openstack/
satellite6/controller/terraform/**openshift_virtualization**/rhv/insights) + their
paired managed credential types ship in `awx-plugins`. **No controller code needed
to add any of them.** The one gap: the **"supported"-variant routing** (the
`redhat.*`/`ansible.*` FQCNs) is gated by the same product-name check as F-CRED,
and requires the paired `redhat.*` collections in the EE. Cost is **live-counterpart
test realism**, stratified: ship-first (self/kubevirt/terraform/scm ≈ trivial);
container-simulatable (ec2 LocalStack, vmware vcsim, satellite Foreman, openstack
DevStack); defer-on-demand real-account (azure/gce/rhv; insights is OUT — mock only).
Effort ≈ **notify 11–12 + inv 8 enablement + ~18 cloud-test-infra; ~2 net-new (shared gate).**

### 4.5 F-OPS + F-SCALE + F-RBAC  — net-new ≈ backup/restore (~6 days) + tests

**~90% INHERITED/enablement.** Settings registry (~98 controller `register()` +
DAB), external log aggregators (`utils/external_logging.py` rsyslog `omhttp`;
Splunk/Logstash/Loggly/Sumologic/other), all four cleanup commands, the full
capacity math (`utils/common.py`, `models/ha.py`), per-IG `max_forks`/
`max_concurrent_jobs`/`policy_instance_*`, the deprecated `/roles/` shim
(`views/__init__.py:4860+`, backed by legacy `models/rbac.py`), 38 role types +
36-entry DAB mapping, and gateway-JWT auth wired **first** (`AwxJWTAuthentication`)
are all present. **The one genuine net-new deliverable: pod-native backup/restore**
(§5.2) — upstream ships it via awx-operator, absent from this pod-only fork.
Conditional net-new: wire DAB `ServiceTokenAuthentication` (`X-ANSIBLE-SERVICE-AUTH`,
present in DAB, **unwired in awx**) if cross-service tokens are needed, else mark
inert. **Riskiest: the DAB↔legacy-`Role` dual-write** behind `/roles/`
(`_sync_old_rbac`) — a silent-failure surface deserving a bidirectional property
test against a prod DB copy. Effort ≈ **71 days (~40 enablement/settings-audit,
~6 net-new backup/restore, rest tests).**

### 4.6 F-MESH  — net-new = ops plumbing, ~0 controller code (demand-gated)

**Overwhelmingly INHERITED**, and the seam is **already live**: the controller
*always* speaks receptor (`tasks/receptor.py AWXReceptorJob`), and pod-only just
means `work_type` resolves to `kubernetes-*-auth` — the mesh path
(`ansible-runner` routed to `execution_node`) is dormant but compiled. Models,
`/instances/` API, install-bundle generation with CA-signed certs, health/capacity
loops, node-lifecycle commands, and the mesh visualizer are all present; receptor
itself is a healthy external Go project (`receptorctl==1.6.0` pinned). **Net-new is
not controller code** — it is (1) **persist the mesh CA + work-signing keypair**
(today ephemeral per-pod — the one thing to fix *now*, §5.3), (2) TCP listener +
control-node peering, (3) a **real remote-node VM test estate**, (4) receptor Go
stewardship. **Recommendation: keep F5 demand-gated** (no course/product needs it),
**but actively preserve the seam** — never delete mesh code, keep `work_type`
data-driven, persist the CA now. Effort ≈ **12–15 eng-weeks + a standing VM tier,
almost none of it Python.**

## 5. The genuine beyond-upstream frontier — net-new controller code

The entire net-new *code* surface for full parity (excluding demand-gated mesh
build-out) is the following bounded set. Everything else is inherited-and-tested
or enablement.

### 5.1 Product-name gate → branding-neutral runtime identity  ·  ~2–3 days  ·  HIGHEST LEVERAGE

`awx/main/models/credential.py:669,689` disables **all external-secret credential
plugins** *and* the **"supported" cloud credential/inventory types** unless
`detect_server_product_name() != 'AWX'`. That function
(`awx_plugins.interfaces/.../_temporary_private_licensing_api.py`) returns `'AWX'`
unless `/var/lib/awx/.tower_version` exists (in which case it returns the Red Hat
trademark string). Our branding rules ban **both** strings. **Design:** a minimal
patch (`patches/` queue) so the runtime reports a fork-controlled neutral product
name that satisfies `!= 'AWX'` without using the Red Hat trademark — implemented
by dropping a fork sentinel file the shim reads, or patching the shim to a neutral
constant. **Acceptance:** a test asserting all 11 credential plugins **and** the
supported inventory/credential variants register when the neutral identity is
active, and that no banned brand string appears. This single patch unlocks the
largest swath of "supported" AAP functionality of any item on the list.

### 5.2 Pod-native backup/restore  ·  ~6 days

Upstream's backup/restore is delivered by **awx-operator** (`AWXBackup`/`AWXRestore`
CRs); the pod-only fork does not inherit it, and no backup command exists in the
awx tree. **Design:** a rehearsed runbook + scripts covering `pg_dump`/restore of
the controller DB, **`SECRET_KEY` custody** (the decryption root for all
`$encrypted$` fields — backup is worthless if the key isn't recoverable),
settings/config export, and the EE/registry references. **Acceptance:** restore
into a clean DB on a prod1 copy with exact row counts and a proven
`$encrypted$`-field decrypt after restore (ties to CTL-013). This is the one item
that is genuinely *missing operational capability*, not merely untested.

### 5.3 Persist the mesh CA + work-signing keypair  ·  ~1–1.5 wk (mostly ops)

`deploy/scratch/stack.yaml`'s `init-receptor-runtime` generates a self-signed mesh
CA + work-signing key **per pod, ephemerally**. Harmless for local k8s submission,
**fatal to any future mesh** (a bundle signed by pod A is untrusted after A
restarts or a second control replica answers). **Design:** generate the mesh CA +
work-signing keypair **once at cluster bootstrap** into a shared read-only Secret
mounted into all control/task pods, with a documented rotation drill and a **loud
failure** when a stale-signed bundle is presented. Doing this now (even pod-only)
makes "add a listener + peers" the entire remaining mesh delta. **Acceptance:** CA
survives a control-pod restart and a scale-to-2; a stale bundle is rejected with a
clear error.

### 5.4 (Conditional) wire `ServiceTokenAuthentication`  ·  ~3 days or mark inert

DAB provides `ServiceTokenAuthentication` (`X-ANSIBLE-SERVICE-AUTH`) but awx does
not wire it. Needed only if the controller must accept **cross-service** tokens
from hub/EDA directly (vs. user/service-account JWTs, already handled).
**Decision:** wire + live-test if in scope; else record *accepted-inert* with the
justification that the gateway fronts service-to-service auth. Do not silently omit.

> **§5 is the whole net-new code answer:** items 5.1 + 5.2 (+5.3 seam, +5.4
> conditional) ≈ **~2–3 focused weeks of controller code**. There is no large
> hidden controller to build.

### 5.5 High-value inherited *unlocks* (0 net-new code; enablement wins)

Not net-new, but worth calling out because they are AAP 2.6/2.7 capabilities that
are **already wired in the controller and merely disabled** — enabling them is a
config + test task, and each is a real product differentiator:

- **OPA policy-as-code** — `evaluate_policy()` runs before every job
  (`tasks/jobs.py:670`), `opa_query_path` is a first-class field (migration `0197`),
  gated only by `OPA_HOST/PORT` being set. **Enable + point at an OPA sidecar +
  test** and the platform has policy-as-code — a capability the ledger wrongly
  wrote off as OUT. Highest-value unlock after §5.1.
- **The §5.1 product-name gate is itself an unlock** — flipping it turns on the
  entire external-secrets + supported-cloud surface at once.
- **Self-hosted analytics/host-metrics sink** — the collector machinery is inherited;
  only the console.redhat.com destination is OUT. If ever wanted, it can target a
  self-hosted sink with no new controller code.

## 6. Net-new engineering designs

The seams for the breadth clusters are in §3 (adopt-as-is). The net-new *code*
designs are in §5.1–5.4. Two cross-cutting designs remain:

- **The DAB↔legacy-`Role` consistency test (F-RBAC).** `_sync_old_rbac` replays
  gateway JWT claims into `Role.members` per request under `disable_rbac_sync()`
  (so drift leaves no activity-stream trace). Design a **bidirectional property
  test**: for every assignment entry point (`role_user_assignments`, team grant,
  gateway claim, bulk_create), assert the legacy `/roles/N/users|teams/` read
  agrees, and vice-versa where writable — run against a prod1 DB copy. This guards
  the one place two RBAC systems must stay consistent.
- **The settings audit ledger (F-OPS).** Enumerate from
  `settings_registry.get_registered_settings()` (not docs); one row per key marked
  BEHAVIOR (→ a test) or INERT (→ a justification class: SaaS/OUT, gateway-owned,
  subscription); a CI meta-test fails on any unruled key. Turns the boring sprawl
  into a self-policing regression gate across the monthly rebase.

## 7. Revised effort model & sequencing

Re-derived as a **sum over §4 buckets** — separating net-new *code* from
enablement from conformance/test-realism:

| Cluster | Net-new code | Enablement + conformance | Live test-infra (dominant cost) |
|---|---|---|---|
| F-API + F-CLI | 0 | ~26–30 d | `ansible.controller` live-collection lane |
| F-EXEC + F-CONTENT | 0 | ~27.5 d | signing hub + fact-cache pod round-trip |
| F-CRED | ~2–3 d (§5.1) | ~3–5 d | Vault/Conjur/SecretServer/LocalStack + contract doubles |
| F-NOTIFY + F-INV | 0 (shares §5.1) | ~19–20 d | notification sinks + cloud accounts/sims |
| F-OPS + F-SCALE + F-RBAC | ~6 d (§5.2) | ~40 d | live log sinks (Splunk/Loki/Logstash) |
| F-MESH (demand-gated) | ~0 (ops: §5.3) | — | **standing VM tier w/ real remote nodes** |

**Totals.** Genuine net-new **controller code ≈ 2–3 weeks** (§5). The
`FULL-PARITY-PLAN`'s ~26–32 engineer-weeks for F1–F4 is confirmed in magnitude but
**re-attributed**: it is ~90% conformance-test authoring + live-counterpart
test-infrastructure + the settings audit, not feature development. Mesh (F5) is a
separate ~12–15 weeks + a VM estate, **demand-gated**, almost entirely ops.

**Sequencing** (refines the plan with the audit's start-conditions):
1. **§5.1 product-name gate first** — cheap, and it *unlocks* the F-CRED and F-INV
   surfaces the later milestones test. Nothing in F-CRED/F-INV is real until it lands.
2. **F1** — stand up the `ansible.controller` live-collection lane + OpenAPI golden
   diff; hardens the surface + becomes a rebase regression guard.
3. **F2** — freeze the precedence tables, then run them live (nested-workflow artifacts first).
4. **F3** — build the three live-test harnesses (§3) once, then add backends
   demand-first (self-hostable before cloud accounts).
5. **F4** — the settings audit ledger + `/roles/` consistency test + **§5.2 backup/restore**.
6. **F5 (mesh)** — demand-gated; do **§5.3 now** to hold the seam, build the rest only on product demand.

Cross-cutting, always-on: the **stewardship tax** (CTL-072 monthly rebase + CVE
watch) and the rule that **every conformance test is also a rebase tripwire**.

## 8. The honest answer to "what needs to be developed"

The controller's *code* is largely upstream `devel` (the maintained AAP 2.7 line);
the controller's *engineering* is three things, and only the first is truly novel
per feature:

1. **A small, bounded net-new set (§5)** — the branding-neutral product-name gate,
   pod-native backup/restore, the mesh-CA seam fix, and a conditional service-token
   wire. ~2–3 weeks of code, not a controller.
2. **The owned hard cores in `DESIGN-AGENDA.md`** (D-2 job-lifecycle state machine,
   D-4 event pipeline, D-7 scheduler, D-8 FMEA, D-10 observability) — the genuinely
   *hard* engineering, largely delivered by the shipped patch queue and the scoped-1.0
   work, and where any *future* deep investment belongs.
3. **The proof discipline (§2)** — turning inherited breadth into *demonstrated*
   parity via conformance tests + live counterparts. This is the bulk of the
   "full-parity" cost, and it is test/infrastructure work, not feature code.

So: **"full AAP 2.7 parity beyond upstream" is earned mostly by *proving* what we
inherit and by standing up realistic test counterparts, plus roughly three small
patches — not by re-writing a controller.** The ledger stays the scoreboard; each
release publishes the delta; the claim is `N/M rows tested, K interpreted`, never
an unqualified word.

---

### Ledger corrections proposed by the audit

Ranked by materiality (the code contradicts the ledger in these places):

1. **OPA policy-as-code — MISRULED, the marquee correction.** `PARITY-LEDGER.md`
   §7 rules it `OUT (revisit)` ("platform's policy repo covers the need"). **Wrong:
   it is fully-wired controller code in the pinned `devel`** — `evaluate_policy()`
   runs before job execution (`awx/main/tasks/jobs.py:670`), `opa_query_path` is a
   first-class field on Inventory/JobTemplate/Organization (migration `0197`),
   with `OPA_HOST/PORT/SSL` settings and `tests/functional/test_policy.py`. The 2.6
   "preview" everyone assumes is downstream-only sits **inherited, for free.**
   **Re-rule to IN/FULL-cheap** (enable + point at an OPA server + test) — a genuine
   differentiator the platform can claim now.
2. **Host metrics / indirect node counting — CONFLATED.** §3 rules the whole row
   `OUT`. The **counting/audit code is inherited** (`IndirectManagedNodeAudit`,
   `host_metric*` commands, `collectors.py`, migration `0196`); only the
   **RHSM/candlepin entitlement *enforcement*** is OUT. **Split the row.**
3. **Automation Analytics — NUANCE.** §7 `OUT` is right for the *destination*, but
   the **collector code is inherited** (`analytics/collectors.py`, `OIDCClient`,
   disabled by default). Note only shipping-to-console.redhat.com is the SaaS
   coupling; the gather machinery could target a self-hosted sink.
4. F-EXEC / F-NOTIFY / F-INV / F-CRED plugin rows: re-mark **"FULL (build)" →
   "INHERITED — conformance/enablement pending"** (code present; owed *tests*).
5. F-API/F-CLI: **split `ansible.controller` (buildable here) from `ansible.platform`
   (GATEWAY)**; filter grammar + OpenAPI schema are now inherited from **DAB +
   drf-spectacular**, not awx proper.
6. **MCP server & automation dashboard — re-rule `OUT` → `OTHER-SERVICE`** (verified
   absent from awx; they are separate platform components that *call* AAP APIs — a
   precise reason, not generic exclusion).
7. F-OPS: `cleanup_tokens` is **retired** (migration deletes the SJT) — mark
   *accepted-inert, gateway-issued tokens*. Controller-owned OAuth2 provider is
   **removed** (migration `0204`) — confirm the `/tokens/`,`/applications/` rows as
   GATEWAY.
8. Add the **product-name gate** and **backup/restore** as explicit net-new line
   items; note the ephemeral mesh-CA as a seam-preservation task; flag service-account
   honoring and the F-MESH core as "inherited mechanism; cost = enable + test", not
   net-new build (the "single largest full-parity item" framing overstates the
   *code* delta — the mesh core is inherited; its cost is a VM test estate).

**Verification caveat (honesty):** `docs.redhat.com` blocks automated fetch
(HTTP 403) and the grounded-docs RAG backend was unavailable this session, so the
doc-side rulings rest on search excerpts; the **load-bearing evidence is direct
inspection of the pinned upstream source** (every path above verified). Any ruling
that hinges on documented *behavior* (not code presence) carries an `interpreted`
flag until an executable or live oracle confirms it, per §2.
