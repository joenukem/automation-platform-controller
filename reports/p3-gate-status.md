# Phase 3 / 1.0 release-gate status (live tracker)

Against `docs/REQUIREMENTS.md` §9. Updated as items close.

| gate | status | evidence |
|---|---|---|
| §9.1 P0 on throwaway ci-k3s-vm | **OPEN** | cutover proven natively on prod1 (ahead of plan); clean-room ci-k3s-vm P0 deploy not yet done |
| §9.2 DO467 green @MAX=3 + 3 victims @MAX=8 | **PARTIAL** | victims (11, review-inventory, review-job-template) green @MAX=8; full @MAX=3 blocked by lab-content+hub (NOT controller — see parity-sweep report) |
| §9.3 leak-scan zero orphans / 20 cycles | **DONE** | 20/20 clean, estate verified clean post-run (reports/ctl-040-leak-scan-20) |
| §9.4 cutover rehearsal on prod1 DB copy | **DONE** | Phase-1 report: 235MB dump, 41 migrations clean, then native cutover live |
| §9.5 parity-drivers/ledger updated | **DONE** | parity-drivers.md resolution table: 6 drivers closed by evidence, D5/D6 carried with IDs |

## Phase-3 CTL items (CTL-040..052)
| req | status |
|---|---|
| CTL-040 no stranded resources | DONE — patches 0001/0004/0005, live-proven, NOT NULL enforces I1 |
| CTL-041 resumable teardown | DONE — state machine + pump; patch 0006 closed the failed-retry gap |
| CTL-050 scale correctness | 6/6 concurrent proven; formal 2h MAX>=8 soak awaits a clean webapp window |
| CTL-051 dispatcher survival | **DONE** — queued job survived a force-killed task pod (reports/ctl-051-*) |
| CTL-052 event-latency budget | jobs-list N+1 fixed (patch 0003, 33->13 q); live-tail <=5s under soak not formally captured |

## Governance / build
| req | status |
|---|---|
| CTL-002 mirror-only build | PARTIAL (de-risked) — base images mirrored + MIRROR_BASE wired (zero quay refs); full vendor bundle captured (vendor-capture:full, 125M wheels + 379M RPMs, both stages incl. copr rsyslog). Remaining: VENDORED render transform + deny-egress build (spec in docs/CTL-002-mirror-build-plan.md). |
| CTL-072 stewardship | **DONE** — STEWARDSHIP.md: named owner, monthly rebase process, CVE watch, drop-the-fork path, ledger |

## Remaining — and what each is blocked on

Quick controller/doc items: **all closed** (§9.3, §9.4, §9.5, CTL-040/041/051/072).

The rest each need infrastructure, a clean window, or non-controller work —
none is a further quick win:

| item | blocked on |
|---|---|
| CTL-002 pip/dnf mirror | one egress-allowed capture/sync pass (vendored-build or pulp) — see docs/CTL-002-mirror-build-plan.md; a few hours |
| CTL-050 2h soak + CTL-052 under-load latency | an uninterrupted webapp window (other sessions keep redeploying lab-webapp mid-run) |
| §9.1 ci-k3s-vm clean-room P0 | a throwaway ci-k3s-vm provisioned; deploy/scratch/up.sh manifests are ready to point at it |
| §9.2 DO467 full suite green @MAX=3 | lab-content selector fixes + automation-hub F13/F17 — NOT controller work (parity-sweep proved the controller passes correct content) |
