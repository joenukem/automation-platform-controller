# Design agenda — what must be designed before this controller is real

A direct answer to "is the crux of this project reviewing and testing upstream
git commits?" — **no**. Curating upstream (pinning SHAs, reviewing diffs,
contract-testing the result) is the *supply chain*; it produces parts, not a
controller. A controller is a distributed state machine wrapped in an API, and
the things that make controllers hard — partial failure, concurrency,
lifecycle, and observable truth — are exactly the things upstream commits
cannot decide for us. Each item below is a decision we own, with its
deliverable and the acceptance evidence that closes it.

Rule for every item: **a design is not done until its failure test is named.**
An ADR without an acceptance test is an opinion.

Companions: `PARITY-LEDGER.md` (what "parity" means, feature by feature),
`FULL-PARITY-PLAN.md` (the costed track to full parity),
`RISK-ASSESSMENT.md` (whether this plan is likely to succeed, and on what
conditions).

## D-1 Domain & ownership model — DRAFTED

Who owns what, and what deletion means. → `ADR-0001-organization-ownership.md`
(aggregate-root orgs, deletion as an observable state machine, tombstoned
history, session leases). Acceptance: invariants I1–I5 as property tests +
the CTL-040 20-cycle leak-scan.

## D-2 Job lifecycle state machine — THE CRUX

The heart of the controller and the hardest part to get right:

- Explicit states and legal transitions (`pending → waiting → running →
  successful | failed | error | canceled`), with *who* may cause each
  transition (API, dispatcher, reaper, user cancel).
- Dispatcher **leases with heartbeats**: a running job is a lease held by a
  worker; a dead worker's lease expires and the reaper transitions the job to
  `error` — never "running forever". (Today's engine can strand jobs;
  our fleet's job-state ambiguity comes from this.)
- Cancel semantics: cancel is a *request* recorded on the job; the state
  machine defines what it means in every state, including the race with
  completion.
- Idempotency: every reconciliation action must be safe to repeat; the task
  layer (dispatcherd) delivers at-least-once, so handlers must be
  deduplicating.

Deliverable: state diagram + transition table + invariant list ("no job in
`running` without a live lease", "terminal states are absorbing").
Acceptance: property tests over the transition table + kill-a-worker fault
test (CTL-051) with zero stranded jobs.

## D-3 Execution backend: Kubernetes pods only — DECISION NEEDED (recommend: yes)

Upstream carries receptor mesh, execution nodes, hop nodes — an entire
topology this platform never uses. Recommend: **container-group-style pod
execution is the only backend**; every job is a k8s pod with an EE image, a
service account, and a pod spec. This deletes the largest inherited
complexity mass (mesh CA, receptor protocol, node heartbeats) and aligns the
controller with the substrate we actually run. Needs an ADR with explicit
non-goals so mesh doesn't creep back in.
Acceptance: all DO467 jobs run as pods; no receptor components deployed.

## D-4 Event & output pipeline — the highest-volume data path

Job events dwarf every other write. Our labs already show the symptom: output
asserts need settle-sleeps because event delivery lags job state. Design the
pipeline explicitly: batching, ordering guarantees per job, backpressure when
a job floods (verbosity 5, loops), retention/pruning policy, and a live-tail
latency budget (CTL-052: ≤5s under soak). Decide storage now (same postgres
vs separate table partitioning) — this is the thing that falls over at scale.
Acceptance: flood-job load test with latency histogram; console tail stays
within budget while a 100k-event job runs.

## D-5 API compatibility contract

`docs/api-surface.lock`: extract the endpoints/fields the platform actually
uses (provider, driver, console, lab verifies), freeze as OpenAPI + golden
request/response tests, and adopt a deprecation policy for everything outside
it. Compatibility is a *chosen surface*, not "whatever the old engine did".
Acceptance: CTL-010 contract replay green.

## D-6 RBAC model and migration

DAB's RoleDefinition/assignment model replaced the legacy per-object Role
rows. Decide: which role definitions exist, how legacy roles map, what the
platform's labs actually exercise (execute-vs-admin on templates, org member
vs admin, team grants — the DO467 suite is the concrete inventory of needed
behavior). Acceptance: the RBAC-negative lab steps (bob cannot see scope
controls) pass; migration mapping table tested against a prod DB copy.

## D-7 Scheduler & concurrency model

The frozen engine's global task-manager lock-step is why our CI fabricates
failures above 3 concurrent sessions (evidence: identical labs pass at MAX=3,
fail at MAX=8). Define the capacity model: per-org fairness, instance-group
capacity accounting, what saturates first and what the API does under
saturation (queue visibly, never 5xx). Acceptance: CTL-050 soak — DO467
green at MAX≥8, list p95 ≤2s at 10k jobs.

## D-8 Failure-mode analysis (FMEA)

A controller earns trust by what it does when things break. Enumerate the
fault matrix — postgres restart mid-job, dispatcher OOM, EE image pull
failure, pod eviction mid-play, gateway token expiry mid-poll, event flood,
disk full, clock skew — and for each: detection, blast radius, automatic
recovery, and the injected-fault test that proves it. The platform's history
(silent provider skips, 4xx-as-success, sweeper gaps) says our failure mode
is *silence*; the design rule is **every failure is loud and owned**.
Deliverable: FMEA table; acceptance: one chaos test per row in CI.

## D-9 Data migration & rollback

24.6.1 schema → new schema, rehearsed on a prod1 copy with row counts and a
rollback story (CTL-013). Includes adopting existing orphans (ADR-0001
migration note) and the DAB RBAC mapping (D-6). Green-field cutover stays the
fallback; either way the decision is rehearsed, not hoped.

## D-10 Observability contract

Metrics, structured logs, and liveness signals designed up front: dispatcher
lease-loop heartbeat, GC-loop heartbeat, deletion-state-machine gauges, event
pipeline lag. Principle from our own ops rules: **silence is never evidence
of health** — every loop exports "I ran at T and did N". Acceptance:
awx-telemetry-agent scrapes the catalog; a stalled GC loop fires an alert in
the soak test.

## D-11 Security model

Bootstrap without default credentials, token scopes, credential-secret
encryption key custody and rotation, and multi-tenancy isolation (a session
org must be provably blind to its neighbors — the labs' scope-control
negative checks are the executable spec). Acceptance: CTL-060/061 plus an
isolation test that runs two sessions and cross-probes.

## D-12 Conformance suite as the standing spec

The DO467 suite is the platform's de-facto conformance harness; wire it as
this repo's acceptance layer: contract replay (D-5) + DO467 serial + leak
scan (D-1) + soak (D-7) + chaos rows (D-8). A controller change is releasable
when this suite is green — that, not upstream diff review, is the crux.

## Process to get it right

1. **ADR per decision** (D-1..D-11), each with named acceptance evidence;
   PROPOSED → ACCEPTED only with the test merged.
2. **Spike before commitment** (Phase 0): build and boot the composed stack
   once by hand; feasibility findings feed the ADRs.
3. **Invariant-first testing**: the I-lists in ADRs become property tests
   before feature work starts.
4. **Upstream curation stays subordinate**: pin SHAs, review diffs against
   the ADRs (does this commit violate our ownership model? our state
   machine?), and let the conformance suite — not the diff — decide
   acceptance.
