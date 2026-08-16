# Full-Parity Plan — assessed path from scoped 1.0 to full AAP 2.7 parity

Status: ASSESSED PLAN · 2026-08-16 · Consumes the FULL clusters of
`PARITY-LEDGER.md`. Companion honesty document: `RISK-ASSESSMENT.md`.

## Verdict up front

Full parity is **reachable but expensive, and most of its cost buys nothing
this platform uses today**. The plan below sequences it so that every
milestone ships value on its own, the expensive tail (mesh) is last and
separately decidable, and "full parity" is a summable claim over ledger
clusters rather than a vibe. Estimates are in **focused engineer-weeks**
(one person or an equivalent agent lane, full-time); they assume scoped-1.0
is DONE (state machine, event pipeline, conformance suite all in place) —
that foundation is what makes the clusters mostly mechanical.

## Milestone F1 — API completeness (F-API, F-CLI) — ~6–8 weeks

Full filter grammar (`__search`, `chain__`, `or__`, `not__`), named URLs,
copy endpoints, bulk launch, complete activity-stream coverage, OpenAPI
schema endpoint, then `awx` CLI and `ansible.controller`/`ansible.platform`
collection conformance runs in CI.

- Why first: it hardens the surface everything else lands on, the collection
  compatibility directly unlocks configuration-as-code courses (s08 class),
  and the OpenAPI endpoint upgrades our own CTL-010 contract tests.
- Risk: LOW. Oracle: collection integration tests are public and runnable.

## Milestone F2 — Execution semantics depth (F-EXEC, F-CONTENT) — ~6–8 weeks

Workflow-level prompts/surveys with exact precedence, nested workflows,
complex multi-rule schedules, prompted schedules, fact caching + injection,
provisioning callbacks, manual/archive projects, signed-content verification.

- Why second: precedence semantics are where subtle incompatibilities hide;
  doing them while D-2's state machine team context is fresh is cheapest.
- Risk: MEDIUM — precedence rules must match documented behavior exactly;
  each rule becomes a table-driven test before code.

## Milestone F3 — Integration breadth (F-CRED, F-NOTIFY, F-INV) — ~8–10 weeks

Credential plugins (Vault KV first, incl. 2.7 OIDC auth; then Conjur, Azure
KV, AWS SM, per demand), the notification-type matrix (email, Slack,
PagerDuty, Grafana, Twilio, Mattermost, Rocket.Chat, IRC), GitLab/Bitbucket
webhooks, cloud inventory plugins (ec2, azure_rm, gce, vmware, openstack,
satellite, terraform, OpenShift Virtualization).

- Nature: wide, shallow, parallelizable — ideal fleet work once the shared
  frameworks (secret-lookup interface, notification backend interface,
  inventory-plugin harness) are designed in-session first.
- Risk: LOW-MEDIUM per item; the real cost is *test realism* — each plugin
  needs a live counterpart (a Vault, a Slack-compatible sink, a cloud
  simulator or real account). Budget test infrastructure explicitly;
  a plugin without a live test is not shipped (no verify-on-existence).

## Milestone F4 — Operations completeness (F-OPS, F-SCALE, F-RBAC tail) — ~6 weeks

Full settings surface, log aggregators, system cleanup jobs, retention
policies, full capacity-policy surface (max_forks/max_concurrent per IG,
policy instance lists), legacy `/roles/` compat API, full granular role
matrix, service-account honoring.

- Risk: LOW-MEDIUM. Mostly enumeration discipline; the settings sprawl is
  boring, but every setting needs a behavior test or explicit "accepted, inert"
  marking — silent inert settings are how fake parity happens.

## Milestone F5 — Automation mesh (F-MESH) — ~12–16 weeks, SEPARATELY DECIDABLE

Receptor integration, execution/hop node lifecycle, install bundles, node
health/capacity API, mesh visualizer data, work signing.

- This is the only cluster that changes the architecture (D-3 currently
  rules pod-only). Receptor itself is healthy upstream (active, Jul 2026),
  so the parts exist; the cost is topology lifecycle + security (work
  signing, CA) + a test lab with real remote nodes (VM tier).
- **Recommendation: do not build F5 on parity grounds alone.** Trigger it
  only from product demand — a course teaching mesh (the DO374/DO467 line
  does not), or an edge-execution product need. Until triggered, full parity
  is claimed as "full parity excluding mesh (ledger F-MESH: deferred,
  decision documented)".

## Cross-cutting rules for the whole track

1. **Oracle discipline** — for every cluster, name the behavioral oracle
   before building: public collection/CLI test suites (F1), AAP 2.7 docs
   tables turned into table-driven tests (F2), live counterpart services
   (F3). Where the docs are ambiguous and no public test exists, the ledger
   entry gets an "interpreted" flag rather than a silent guess.
2. **Ledger is the scoreboard** — a cluster is done when every one of its
   ledger rows flips to shipped-with-test; releases publish the delta.
3. **Conformance suite grows with each milestone** — F1 adds the collection
   conformance job, F2 the precedence tables, F3 the live-integration jobs;
   nothing merges on code review alone.
4. **Stewardship tax is continuous** (CTL-072): monthly upstream rebase,
   CVE watch, and the fork-ownership cost apply across all milestones and
   after them, forever or until upstream resumes releases.

## Totals and honest odds

- F1–F4: **~26–32 engineer-weeks** after scoped-1.0; parallelizable to
  roughly 3–4 calendar months with fleet lanes on F3/F4 breadth.
- F5 (mesh): **+12–16 weeks** and a VM-tier test estate; only on demand.
- Scoped-1.0 itself (the prerequisite) is the riskiest single block — its
  odds are governed by the Phase-0 fallback gate (CTL-071), not by this
  track.

**Assessment:** with scoped-1.0 delivered and the oracle discipline held,
F1–F4 full-parity-except-mesh is a *likely* outcome — it is breadth on a
proven core, the kind of work this platform's fleet executes well. Claiming
**total** full parity including mesh is achievable but should be a demand
decision, not a completeness reflex; the ledger keeps the claim honest
either way.
