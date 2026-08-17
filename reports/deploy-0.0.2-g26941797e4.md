# Deploy: controller 0.0.2-g26941797e4 — prod1 + franken (Automation Platform identity)

Date: 2026-08-17

## What shipped

The newest controller image built from the full committed patch queue
(`patches/series` 0001–0008), pinned upstream at `sources.lock`
(awx `3fea070420`, DAB `f90ed8ae`, awx-plugins `7c6a7cf9`, dispatcherd
`2026.3.25`, awx_plugins.interfaces `b52a9f80`).

- **Image:** `franken-registry.example.com:5000/automation-platform/controller:0.0.2-g26941797e4`
  (push registry `192.168.1.240:30500`, image id `e4604a72a6f3`).
- **Reports as:** product name **`Automation Platform`**, version `25.0.0.dev0`.

### New in this build (vs the previously-deployed 0.0.2-g9de9502ff9)

- **patch 0007** — enable the Automation Platform plugin surface + product identity:
  external-secret credential plugins (HashiCorp Vault incl. 2.7 OIDC, Conjur,
  CyberArk AIM, Azure KV, AWS SM, Delinea/Thycotic, Centrify, GitHub App),
  the *supported* managed credential types (aws/azure_rm/gce/vmware/openstack/
  satellite6/rhv/terraform), the *supported* inventory sources, and the
  `X-API-Product-Name` / UI product name = `Automation Platform`.
  **Licensing is deliberately left untouched** (`licensing.py:554` still keys on
  `detect_server_product_name() == 'AWX'` → `OpenLicense`), so there is **no
  RHSM/candlepin subscription enforcement** — product identity + plugin surface
  are decoupled from subscription enforcement.
- **patch 0008** — test-only: make `test_tasks.py:test_managed_injector_redaction`
  robust to the `kind='external'` SimpleNamespace registry entries that 0007
  legitimately adds (`getattr(cls,'injectors',None)`). Image bytes unchanged
  (sdist excludes tests); restores the unit tripwire baseline.

## Verification

### Build tripwire (unit subset, `build/test.sh`)
`reports/pytest-unit-0.0.2-g26941797e4.txt`: **1235 passed / 13 failed / 116 errors**.
The 13 failed + 116 errors are identical to the known no-DB baseline (CTL-002);
+2 passing vs baseline are the newly-registered supported managed types passing
the same redaction contract. Zero new failures/errors from the patch; collection
healthy (0008 fixed the 0007-surfaced collection abort).

### Image content (installed venv source)
Product-name gate baked at `generics.py:287` and `ui/urls.py:18` = `'Automation
Platform'`; `credential.py` registers base+supported managed + external plugins
unconditionally; `inventory.py` loads `inventory.supported`. `licensing.py`
unchanged. `awx_plugins.credentials` enumerates 12 external plugins incl.
`hashivault-kv-oidc`/`hashivault-ssh-oidc`.

### prod1 (`automation-platform` ns) — roll-forward
- `awx-controller-web` (3 replicas) + `awx-controller-task` rolled to the new tag,
  rollout green; migrations applied on the same controller line.
- `GET /api/v2/ping/` → `200`, header `X-API-Product-Name: Automation Platform`,
  `version 25.0.0.dev0`, task node heartbeating (capacity 315).
- DB now has all 10 external credential types (`kind='external'`) and the
  supported managed types — previously gated off under the AWX identity.

### franken (`automation-platform` ns) — fresh stand-up cutover
The `oap-automation-platform-controller-*` stack was still on the **frozen
`ansible/awx:24.6.1`** engine with an **uninitialized DB** (web 500-crash-looping
3+ days: `relation "django_migrations" does not exist`). This was a fresh
stand-up, not a data migration (no data at risk).

1. `set image` web+task `awx-web`/`awx-task` → `0.0.2-g26941797e4`.
2. **Settings fix:** the mounted `/etc/tower/settings.py` (ConfigMap
   `oap-automation-platform-controller-settings`, key `settings.py`) hardcoded the
   removed cache backend `awx.main.cache.AWXRedisCache`. Patched to
   `ansible_base.lib.cache.redis_cache.DABRedisCache` (matches prod1's working
   value; TCP LOCATION preserved). **Durability:** this is a live-CM edit — the
   deploy chart source must carry the same change or a `helm upgrade` will revert
   it (follow-up in the oap chart repo). Backup of the original CM:
   `scratchpad/franken-ctl-settings.orig.json`.
3. Reset the half-applied partial schema (`DROP SCHEMA public CASCADE; CREATE
   SCHEMA public` — no data), then `awx-manage migrate --noinput` from the web
   pod to completion (all migrations incl. `main.0208/0209/0210` — the
   org-deletion / inventory-org-NOT-NULL patches).
4. Recycled the task pod so its `seed-e2e-project` init ran against the migrated
   DB → task `2/2 Running`, web `1/1 Running`.
- `GET /api/v2/ping/` → `200`, `X-API-Product-Name: Automation Platform`,
  `version 25.0.0.dev0`, task node registered `control` capacity 1280,
  heartbeating. Same 10 external + 8 supported credential types in DB.

## Final state
Both clusters run **only** `automation-platform/controller:0.0.2-g26941797e4` on
the controller (`awx-web`/`awx-task`) containers; no stale controller-image pods.
The `receptor` sidecar's `ansible/awx-ee:24.6.1` is the permitted execution-
environment artifact (not the engine). Franken's `default` execution instance
group has capacity 0 (no execution node yet) — a topology matter, independent of
this build/deploy.

Notes:
- Franken's separate `awx` namespace runs an **awx-operator**-managed upstream
  AWX 24.6.1 instance — a distinct reference deployment, not the Automation
  Platform product stack; out of scope for this cutover.
