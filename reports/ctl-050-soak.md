# CTL-050 — scale/soak: thresholds MET; 2h sustained run in progress

**Status: the CTL-050 thresholds are met at the required load** (10 concurrent
sessions, 10k historical jobs). A 2-hour sustained run is underway to complete
the literal "sustained for 2 hours" clause.

## Requirement

10 concurrent lab sessions each provisioning, launching jobs, and tearing down,
sustained 2h, with: **no 5xx from list endpoints**, **provisioning p95 ≤ 60s**,
**list endpoints p95 ≤ 2s at 10k historical jobs**.

## Harness

`build/soak.py` — N concurrent workers, each looping: provision
(org→inventory→project→job_template) → hammer the four list endpoints
(`jobs`, `unified_jobs`, `inventories`, `job_templates`) → tear down (async org
deletion). Reports provisioning p95, list p95/p99, and 5xx count against the
thresholds. Run as an in-cluster **Pod** (`soak-runner`) hitting the service
directly — a single `kubectl port-forward` serializes concurrent streams and
fabricates ~7s latencies that are not the controller's (measured and ruled out).

Setup: a dedicated `ctl-soak` namespace (deployed by `up-cleanroom.sh`, isolated
— no other session touches it, which is what made the soak possible without a
"quiet webapp window"); 10,000 historical `Job` rows seeded via the ORM
(batched `create()` — AWX's multi-table inheritance rejects `bulk_create`).

## Result — PASS at the required load

180s calibration, 10 workers, 10k historical jobs, web 3×(4 CPU) + postgres 4 CPU:

| metric | measured | threshold |
|---|---|---|
| list endpoints p95 | **0.89s** (p99 1.07s) | ≤ 2s |
| provisioning p95 | **2.4s** | ≤ 60s |
| 5xx from list endpoints | **0** | 0 |
| errors | **0** | — |
| throughput | 472 provisions + teardowns, 1888 list ops / 180s | — |

## The resourcing curve (this is a sizing conclusion, not a controller defect)

The list endpoints are CPU-bound (DRF serialization of 20 jobs with the EE
prefetch from patch 0003). Single-request baseline is ~0.5s; under 10-way
concurrency the p95 is set by how much CPU the deployment gives the web tier and
postgres. Scaling it down cleanly:

| config | list p95 | prov p95 | 5xx |
|---|---|---|---|
| web 1×(1 CPU), pg 500m | 7.1s | 31s | 0 |
| web 3×(1 CPU), pg 500m | 4.9s | 12s | 0 |
| web 3×(4 CPU), pg 500m | 2.9s | 6.4s | 0 |
| web 3×(4 CPU), pg **4 CPU** | **0.89s** | 2.4s | 0 |

Two facts fall out: (1) **zero 5xx and zero fabricated failures at every rung** —
the concurrency-correctness that the frozen engine lacked (D4) holds regardless
of sizing; the candidate's patch-0003 N+1 fix is what makes list latency merely a
CPU-scaling problem instead of a query-explosion one. (2) The `deploy/scratch`
manifests ship web at **1 CPU / 1 replica** — fine for functional tests, too small
for the 10-session SLO. A production deploy must size web to ~3×4 CPU and
postgres to ~4 CPU to hold list p95 ≤ 2s at 10 sessions / 10k jobs. **Recommend
raising the shipped `deploy/` web/postgres requests+limits accordingly** (tracked
here; the scratch profile stays small).

## Pitfall recorded

`deploy/scratch` postgres uses **emptyDir** — any postgres restart (e.g. a
`kubectl patch` of its resources) **wipes the DB**. Set resource limits and seed
data *after* the last postgres restart, or give postgres a PVC for a long soak.

## CTL-040 under load

Sampled mid-soak: **0 organization-less inventories**, org count oscillates only
with in-flight provision/teardown — the async deletion machine keeps pace at 10
concurrent, no strand accumulation.

## In progress

`soak-runner` Pod running `DURATION=7200` (2h) at 10 workers; holding
list p95 ~0.83s / prov p95 ~2.3s / 0 5xx across the opening ticks. Final numbers
appended on completion.

## CTL-052 (P2) — separate

Event-latency (console output ≤5s under load) needs **real job execution** (a
working EE + container group); the soak seeds job *records* and exercises the
API/list/provision paths, not live playbook runs. Tracked separately.
