# §9.1 — self-contained clean-room deploy + P0 conformance: PROVEN

**Status: self-containedness + full P0 conformance PROVEN on prod1 in an isolated
namespace.** The one remaining formality is running the same manifests on a
literally separate throwaway ci-k3s-vm (a portability step — see "Remaining").

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

## Remaining for §9.1 literal sign-off

Provision a throwaway **ci-k3s-vm** and run `up-cleanroom.sh` against it, then
`verify.sh`. This is now a portability formality, not engineering: postgres is
emptyDir (no storageclass assumption), all images pull from the franken registry
a ci-k3s-vm can reach, and dex is not required. Size the VM near the pool's
~10Gi guest ceiling (web+task ~2Gi limit each + postgres/redis/gateway/gw-pg).
