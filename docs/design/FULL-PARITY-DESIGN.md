# Full-Parity Design — the engineering design and proof discipline for genuine AAP 2.7 parity

Status: **IN PROGRESS** · 2026-08-17 · Companion to `PARITY-LEDGER.md` (what
parity means), `FULL-PARITY-PLAN.md` (the costed sequence), and `DESIGN-AGENDA.md`
(the owned decisions D-1..D-12). This document adds the layer those three do not:
the **code-grounded engineering design** for closing the FULL clusters, and the
**proof discipline** that makes "full parity" a demonstrated claim rather than an
asserted one.

> Cluster tables and the net-new engineering designs (§4–§6) are being filled
> from a code-grounded audit of the pinned upstream tree (`upstream/awx`,
> `upstream/awx-plugins`, `upstream/django-ansible-base`, `upstream/dispatcherd`)
> against AAP 2.7 documentation. Sections marked _[audit pending]_ are stubs.

## 1. The premise that reshapes the whole effort

The controller **is** the upstream `ansible/awx` `devel` line (pinned in
`sources.lock`) plus a small `patches/` queue. Red Hat's AAP 2.7 controller is
the *same* line plus downstream product integration. Therefore **most of the
"AAP 2.7 controller feature surface" is already in the box** — it is inherited,
not written. The verified example: the entire notification-backend set
(`awx/main/notifications/{email,slack,pagerduty,grafana,irc,mattermost,rocketchat,twilio,awssns,webhook}_backend.py`)
and the API framework (`awx/api/generics.py`, filtering, named URLs, copy views)
ship upstream today.

The corollary is that "full parity" work sorts into three buckets, and **being
honest about which bucket each feature is in is the single most important thing
this document does** — because the failure mode of parity projects is counting
inherited code as delivered work, or shipping a feature that "exists" but was
never proven to behave like the reference.

### 1.1 The three-bucket taxonomy (every FULL ledger row gets one)

| Bucket | Definition | Parity work required | Danger |
|---|---|---|---|
| **INHERITED** | Present and functional in the pinned upstream as-is. | A **conformance test** that pins the behavior; nothing else. | Claiming it "for free" with no test — regressions on rebase go unseen. |
| **ENABLEMENT-GAP** | Code exists upstream but is off / unwired / unconfigured / untested in our build (a setting default, a disabled backend, a missing credential type, an EE without the collection). | Config + wiring + a **live** test. | "It's in the code" ≠ it works in our deployment. |
| **NET-NEW** | Genuinely absent from `awx` + `awx-plugins` + DAB. The real *beyond-upstream* frontier. | Actual new controller code + design + test. | Under-scoping (it's rarely zero) or over-scoping (writing what's actually inherited). |

The audit in §4 assigns every FULL-cluster feature to a bucket **with a cited
upstream path** (or a cited absence). The effort model (§7) is then a sum over
buckets, not a vibe — INHERITED costs test-days, ENABLEMENT costs wiring+test-days,
NET-NEW costs design+code+test-days.

## 2. What "genuine" means — the proof discipline (the anti-fake-parity rules)

"Genuine parity" is a claim about **behavior**, provable without access to run
Red Hat's product (the oracle-weakness risk, RISK-ASSESSMENT §Risk 4). These
rules are normative for every cluster; a feature is not "parity" until it clears
them.

1. **No verify-on-existence.** A feature is not done because the code is present
   or the endpoint returns 200. It is done when a test drives the *documented
   behavior* and asserts the *documented result*. (This repo's own history —
   4xx-as-success, silent provider skips — is the cautionary tale.)

2. **Name the oracle before building.** Every feature declares its behavioral
   reference up front, from strongest to weakest:
   - **Executable oracle** — a public test suite we can run: the
     `ansible.controller`/`awx.awx` collection integration tests (F-API/F-CLI),
     awxkit's own tests, the upstream awx API tests. Strongest; use wherever it
     exists.
   - **Documentary oracle** — an AAP 2.7 docs table turned into a **table-driven
     test** (variable/survey/prompt/schedule **precedence** is the canonical
     case: each documented precedence row becomes one assertion).
   - **Live-counterpart oracle** — for integrations (F-CRED, F-NOTIFY, F-INV), a
     real service the feature talks to: a Vault, a Slack-compatible webhook sink,
     a cloud account or simulator. **A plugin without a live test is not shipped.**
   - **Interpreted** — where docs are ambiguous and no public test exists, the
     ledger row is flagged `interpreted`, the assumption is written down, and it
     is never a silent guess.

3. **Test-or-mark-inert for the settings sprawl.** Every `/settings/` key either
   has a behavior test or is explicitly recorded as *accepted-and-inert* (present
   in the API for compatibility, provably no effect). Silent inert settings are
   how fake parity ships.

4. **The ledger is the scoreboard.** A cluster is done when every one of its
   ledger rows flips to *shipped-with-test*; each release publishes the delta.
   Parity is a **sum over tested rows**, reported as `N/M rows, K interpreted`.

5. **Rebase-durability.** Because we track upstream, every conformance test is
   also a **regression tripwire** for the monthly rebase (CTL-072). Inherited
   features especially need tests — they are exactly the behaviors a silent
   upstream change can break.

## 3. Shared engineering patterns (designed once, reused across clusters)

Three of the FULL clusters (F-CRED, F-NOTIFY, F-INV) are "add another backend"
work. The design leverage is to build/adopt the **plugin seams** once, so each
backend is a small, uniformly-tested unit rather than bespoke code.

- **External-secret lookup seam** — the `awx_plugins.interfaces` contract that a
  credential plugin implements (metadata inputs + a `backend()` callable). _[audit
  pending: confirm the interface shape and which plugins ship in the pinned
  `awx-plugins`.]_
- **Notification-backend seam** — Django-messaging-style backends under
  `awx/main/notifications/`. Verified present; the per-type **config surface +
  message templating** is the parity work. _[audit pending: config completeness.]_
- **Inventory-source injector seam** — source plugin + its credential type +
  injector env; much of the cloud-source logic lives in EE collections, not the
  controller. _[audit pending: controller-side vs EE/collection split.]_

Each seam gets a **live-test harness** (a deployable counterpart + a
table-driven per-backend conformance job) so adding backend N is
config + a fixture, not new test scaffolding.

## 4. Per-cluster audit — inherited / enablement / net-new  _[audit pending]_

_Filled from the 7-cluster code-grounded research. Each cluster: a table
[feature | bucket | upstream path | net-new work | oracle | eng-days], then the
non-trivial designs._

- 4.1 F-API + F-CLI — _[pending]_
- 4.2 F-EXEC + F-CONTENT (incl. the precedence test matrix) — _[pending]_
- 4.3 F-CRED — _[pending]_
- 4.4 F-NOTIFY + F-INV — _[pending]_
- 4.5 F-OPS + F-SCALE + F-RBAC — _[pending]_
- 4.6 F-MESH — _[pending]_

## 5. The genuine beyond-upstream frontier — net-new controller code  _[audit pending]_

_The cross-cutting audit isolates what AAP 2.7 has that upstream `awx devel`
does not, and rules each NET-NEW-controller / GATEWAY-owned / OTHER-SERVICE /
OUT. Candidates under investigation: service accounts & tokens (2.7), Vault OIDC
credential auth (2.7), the `ansible.platform` collection surface, GitHub-App
credentials (2.6+), terraform & OpenShift-Virt inventory (2.6+), and the exact
controller-side residue of the 2.5 gateway split. This section is where the real
"development" — if any beyond the patch queue — is defined._

## 6. Net-new engineering designs  _[audit pending]_

_For each confirmed NET-NEW item: data model, API surface, module/file location,
integration points (dispatcherd tasks, DAB RBAC, gateway trust), migration, and
the named acceptance test. Also the legacy `/api/v2/roles/` compatibility shim
(if net-new) and the execution-backend abstraction seam that keeps F-MESH
additive rather than a rewrite (D-3)._

## 7. Revised effort model & sequencing  _[audit pending]_

_The FULL-PARITY-PLAN's ~26–32 eng-weeks (F1–F4) is re-derived as a sum over the
§4 buckets once the audit lands — separating test-days (INHERITED),
wiring+live-test-days (ENABLEMENT), and design+code+test-days (NET-NEW). Early
signal: the "writing" fraction is expected to be small; the dominant cost is
**test realism** (live counterparts, conformance harnesses) and the **standing
stewardship tax**, not new feature code. The sequence (F1 hardens the surface →
F2 semantics → F3 breadth → F4 ops → F5 mesh demand-gated) is inherited from the
plan; this document adds the per-cluster start conditions and the shared-seam
prerequisites._

## 8. What this changes about the answer to "what needs to be developed"

_[to finalize post-audit]_ The honest through-line: the controller's *code* is
largely upstream; the controller's *engineering* is (a) the owned lifecycle/
failure/observability decisions in `DESIGN-AGENDA.md` (D-2/D-4/D-7/D-8 — the real
hard cores), (b) the small net-new beyond-upstream set in §5–§6, and (c) the
proof discipline in §2 that turns inherited breadth into *demonstrated* parity.
"Full parity" is mostly earned by **proving** what we inherit, plus a bounded set
of net-new code — not by re-writing a controller.
