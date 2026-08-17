# §9.1 — self-contained clean-room deploy + P0 conformance: DONE

**Status: DONE.** Proven twice — first self-contained in an isolated prod1
namespace, then on a **literally separate throwaway k3s cluster** (nested k3s on
prod1). All four `verify.sh` P0 legs green (exit 0) on the throwaway cluster,
including provider provision + teardown + clean leak scan.

## Throwaway-cluster run (the literal §9.1 gate)

A disposable k3s cluster stood up **inside** prod1 (a privileged `rancher/k3s`
pod) — genuinely separate from prod1's own cluster: its own API/etcd, own flannel
CNI, own local-path storageclass, images pulled fresh into its own containerd.
`up-cleanroom.sh` deployed the full stack there (`KUBECONFIG=<inner>`); every pod
came up from a fresh DB, and:
```
surface replay: OK
organization-filter conformance: OK
gateway-issued-token round-trip: OK
ENSURE ok in 32.7s — 7 resources     (CTL-012 provider provision)
DELETE ok in 9.5s
LEAK SCAN clean — provider conformance PASSED   (CTL-040)
verify exit: 0
```

### k3s-in-pod recipe (reusable; the non-obvious parts)
- Mirror `rancher/k3s:<ver>` into the franken registry (the docker image, NOT the
  airgap tarball) and reference it by the `franken-registry…:5000` alias so the
  **outer** kubelet (insecure-registry) can pull it.
- `--snapshotter` default (overlay) but back **only** `/var/lib/rancher/k3s/agent/
  containerd` with an emptyDir (real node fs) — overlay-on-overlay makes the inner
  containerd fail (`unknown service runtime.v1.RuntimeService`); do NOT emptyDir
  the whole `/var/lib/rancher` (that would shadow bundled content).
- `dnsPolicy: Default` on the k3s pod: the stock k3s image has no bundled airgap
  tarball, so the inner cluster pulls `pause`/coredns/local-path from docker.io;
  controller/gateway/postgres images come from the franken registry via a
  `registries.yaml` mirror (`franken-registry…:5000` → `http://192.168.1.240:30500`).
- Mounts: privileged, `/lib/modules` (ro), `/sys/fs/cgroup`, emptyDir `/run` +
  `/var/lib/kubelet`.
- Reach the inner API from the host with `kubectl port-forward pod/k3s-server
  16443:6443` + rewrite the extracted kubeconfig's server to `127.0.0.1:16443`
  (the `--tls-san 127.0.0.1` makes the cert valid).
- Cross-cluster gitea (leg 4): the inner controller reaches the outer gitea
  ClusterIP via an inner `gitea/gitea-http` Service + manual Endpoints →
  `10.43.1.14:3000` (inner pods NAT out through the k3s pod, which can reach the
  outer service network); this is the only cross-cluster shim the P0 gate needs.

## First proof (self-contained, prod1 namespace)

## What this closes

`deploy/scratch/up.sh` **clones** five runtime secrets from prod1's live
`automation-platform` namespace, so it cannot deploy anywhere that namespace
does not already exist — the opposite of clean-room. The new
`deploy/scratch/gen-secrets.sh` + `up-cleanroom.sh` generate every secret from
scratch and deploy with **zero dependency** on the live stack.

## Evidence (namespace `ctl-cleanroom`, controller `airgap-v8`)

1. **Self-contained bring-up.** `up-cleanroom.sh` generated all five secrets
   (`gen-secrets.sh`), applied the stack, and reached a healthy state with no
   reference to `automation-platform`:
   ```
   awx-controller-migrate   Completed        (fresh DB, all migrations incl. 0208–0210)
   awx-controller-postgres  1/1 Running      (emptyDir — no storageclass needed)
   awx-controller-web       1/1 Running
   awx-controller-task      2/2 Running
   awx-gateway              1/1 Running      (came up WITHOUT dex — JWKS fetch is lazy)
   awx-gateway-postgres     1/1 Running
   ```
   `/api/v2/ping/` → `{"ha":false,"version":"25.0.0.dev0",…}` — the fully-patched
   release image.

2. **Full conformance gate green** (`build/verify.sh`, exit 0):
   ```
   surface replay: OK                        (every locked API endpoint 200)
   organization-filter conformance: OK       (ADR-0001 scoped resolution)
   gateway-issued-token round-trip: OK       (ADR-0002 password grant → bearer → /api/v2/me/ 200)
   ENSURE ok in 28.7s — 7 resources          (CTL-012 provider provision)
   DELETE ok in 3.0s
   LEAK SCAN clean — provider conformance PASSED   (CTL-040 no stranded resources)
   ```
   The gateway JWT was issued for `admin@cleanroom.local` — the local user from
   the **generated** `awx-gateway-local-users`, proving the password_hash
   generator matches the gateway's `pbkdf2-sha256:iters:salt:hash` verify format.

## Secret generator (`gen-secrets.sh`) — the crypto material

Validated: RSA signing key parses (`openssl pkey`), dex TLS cert has
`SAN=DNS:dex.<domain>`, the admin `password_hash` round-trips against the
gateway's exact PBKDF2-SHA256 verify (16-byte salt, 32-byte key, 210k iters,
RawStd base64). Internal couplings handled: the gateway postgres password
appears both as `postgres-password` and inside `database-url`;
`trusted-header-signing-secret` is a single value the gateway and controller
both read from the one `awx-gateway-runtime` secret.

## Two image facts folded into the script

- **Controller:** `up-cleanroom.sh` retags the stale `0.0.1-phase0` in the
  manifest to the release image (`airgap-v8`, patches 0001–0006).
- **Gateway:** the stock `gateway.yaml` pins `awx-gateway:0.1.0-aap4`, which
  **predates** the ADR-0002 password grant (returns `unsupported_grant_type`).
  The script now defaults `GW_IMAGE` to `awx-gateway:ropc-pw-117b9305` — the tag
  with the ROPC/local-users identity provider (the one proven live on prod1).

## §9.1 sign-off

Done on a literal throwaway cluster (above). A pool-provisioned ci-k3s-vm would
be equivalent — the nested-k3s run already exercises the same properties (fresh
cluster, no prod1 dependency, self-generated secrets, images pulled fresh) and
does not touch the other agent's ci-k3s-vm pool. postgres is emptyDir (no
storageclass assumption); the stack fits a ~10Gi guest.
