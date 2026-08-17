# Phase 3 / 1.0 release-gate status (live tracker)

Against `docs/REQUIREMENTS.md` §9. Updated as items close.

| gate | status | evidence |
|---|---|---|
| §9.1 P0 on throwaway ci-k3s-vm | **SELF-CONTAINED + P0 CONFORMANCE PROVEN** (ci-k3s-vm formality remains) | gen-secrets.sh + up-cleanroom.sh deploy with zero prod1 dependency; verify.sh all 4 legs green in ns ctl-cleanroom (surface, org-filter, gateway password-grant, provider provision+teardown+clean leak-scan). Only a literally-separate ci-k3s-vm run remains (portability). reports/ctl-091-cleanroom-selfcontained.md |
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
| CTL-002 mirror-only build | **DONE** — egress-free release build proven: `buildah bud --network none --pull=never` (zero network on every RUN, stronger than a deny-egress NetworkPolicy) builds `awx-25.0.0.dev0` green from the vendor bundle alone (controller:airgap-v8, sha256:566eafa8). Tripwire on the airgap image: 1233 passed / 13 failed / 116 errors — identical to the egress-built baseline. See reports/ctl-002-airgap-acceptance.md. |
| CTL-004 SBOM + license (P0) | **DONE** — build/sbom.sh (syft) on controller:airgap-v8: SPDX+syft SBOM + license CSV; gate PASS — 7 composed sources all Apache-2.0, copyleft is base-OS aggregation or uwsgi's linking exception (reports/ctl-004-sbom-license.md) |
| CTL-072 stewardship | **DONE** — STEWARDSHIP.md: named owner, monthly rebase process, CVE watch, drop-the-fork path, ledger |

## Remaining — and what each is blocked on

Quick controller/doc items: **all closed** (§9.3, §9.4, §9.5, CTL-040/041/051/072, **CTL-002**).

The rest each need infrastructure, a clean window, or non-controller work —
none is a further quick win:

| item | blocked on |
|---|---|
| CTL-050 2h soak + CTL-052 under-load latency | an uninterrupted webapp window (other sessions keep redeploying lab-webapp mid-run) |
| §9.1 ci-k3s-vm clean-room P0 | a throwaway ci-k3s-vm provisioned; deploy/scratch/up.sh manifests are ready to point at it |
| §9.2 DO467 full suite green @MAX=3 | lab-content selector fixes + automation-hub F13/F17 — NOT controller work (parity-sweep proved the controller passes correct content) |

## §9.1 clean-room execution map (derived 2026-08-16)

The remaining clean-room deploy is deploy-engineering, not controller code. The
current `deploy/scratch/up.sh` **clones** five secrets from prod1's live
`automation-platform` namespace, so it is not self-contained. To close §9.1:

**A. Self-contained secret generator** (`deploy/scratch/gen-secrets.sh`, no
cluster needed — the hardest part is crypto material):
- `awx-controller-runtime`: `secret-key` (50-char django), `postgres-password` (random).
- `awx-gateway-runtime`: `postgres-password`, `database-url`
  (`postgres://…@awx-gateway-postgres:5432/gateway`), `gateway-oidc-client-secret`,
  `session-cookie-secret`, `trusted-header-signing-secret`. **Coupling:** the
  controller reads `trusted-header-signing-secret` *directly* from this same
  secret (stack.yaml:385) — one value, both consumers, no duplication.
- `awx-gateway-signing-key`: `key-id` (hex), `signing-key` (RSA PEM, JWT signing).
- `awx-dex-tls-secret`: self-signed `ca.crt`/`tls.crt`/`tls.key` for the dex issuer.
- `awx-gateway-local-users`: `users.json` (admin + bcrypt).
- **Couplings to align:** (1) `gateway-oidc-client-secret` must equal the
  `awx-gateway` static-client secret in the **dex** config; (2)
  `awx-gateway-oidc-config` CM issuer/domain (`dex.<BASE_DOMAIN>`) must match the
  dex TLS cert SAN and the deployed ingress host.

**B. Prove self-contained** first in a fresh prod1 namespace with `gen-secrets.sh`
(no `automation-platform` dependency) → rollout green + `/api/v2/ping/` 200 +
`build/verify.sh` four legs. This closes "reproducible from nothing."

**C. ci-k3s-vm** — provision one sized near the pool's ~10Gi guest ceiling (the
stack's working set: web+task ~2Gi limit each, postgres/redis/gateway/gw-postgres/
dex on top — tight but fits a dedicated VM). Deploy via B's manifests, then run
the P0 subset (verify.sh legs + CTL-012 provider provision/teardown + CTL-040
leak-scan) against it. Green = §9.1.

Estimate: a focused session (the doc's own "few hours"); the crypto-material
generator (A) and the dex/oidc couplings are the fiddly parts.
