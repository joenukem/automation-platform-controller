# Phase 0 Report — the composed controller builds, boots, and runs jobs

Date: 2026-08-16 · Gate: CTL-071 · Verdict: **PASSED with two carried items**

## What was proven, end to end, in one session

1. **Build** — rendered the upstream Dockerfile template headless (python3 +
   jinja2, no ansible needed; an ansible-style `bool` filter is the only
   shim), pinned `requirements_git.txt` to our SHAs, stripped the unused
   `--mount=type=ssh`, and built with buildah on the prod1 `image-build`
   pipeline. Result: `automation-platform/controller:0.0.1-phase0`
   (`d666a7850c24`, 813 MB, headless — no UI stage at all). `sources.lock`
   records the exact SHAs.
2. **Boot** — deployed to a scratch `ctl-phase0` namespace by cloning the
   RUNNING stack's manifests (helm release `automation-platform`, chart
   `awx-web-console`) and swapping the image. Scratch postgres 15 + redis.
   All migrations applied cleanly on an empty database, including DAB's
   `setup_managed_role_definitions`. `/api/v2/ping/`:
   `"version": "25.0.0.dev0"`, control node registered.
3. **Provision → launch → teardown** — via the API: org, inventory + host,
   git project synced from the in-cluster gitea (`status=successful`,
   playbook discovery worked), job template on the mirror EE
   (`ansible/awx-ee:24.6.1`), launch → **job `successful`** as a
   container-group pod (`PLAY RECAP ok=1 failed=0`). Teardown exercised
   deliberately as the orphan experiment below.

## Compatibility drift found (24.6.1 settings → devel), all fixed in minutes

| # | Break | Fix |
|---|---|---|
| 1 | `CACHES` backend `awx.main.cache.AWXRedisCache` no longer exists | devel default: `ansible_base.lib.cache.redis_cache.DABRedisCache` |
| 2 | `awx.api.authentication.LoggedOAuth2Authentication` removed (OAuth2 moved to DAB/gateway) | drop it from `DEFAULT_AUTHENTICATION_CLASSES` |
| 3 | (env, not drift) cloned RoleBinding subject kept the old namespace → receptor `Error creating pod: pods is forbidden` | rewrite subject namespace |

Only two real settings drifts to boot the whole devel line against our
production config — far less than feared. The gateway trusted-header auth
(`gateway_auth.GatewayHeaderAuthentication`) imported cleanly.

## Orphan experiment — ADR-0001 confirmed against devel, with a sharper edge

`DELETE /organizations/1/` → 204. Then, unscoped lists:

- `phase0-inv` survives with `organization: null` **and
  `pending_deletion: true` — the async reap never completed** (stuck for the
  rest of the session). A launch against it fails with "inventory is being
  deleted".
- `phase0-prj` survives, `organization: null`.
- `phase0-hello` (job template) survives — and is **degraded**: its
  `inventory` was nulled, so it 400s on launch until re-pointed.

So the devel line does not fix F18; it adds a new failure shape (stuck
`pending_deletion`, degraded-but-visible templates). ADR-0001's aggregate-root
deletion is required work, not inherited.

## Carried items (why the gate is "passed with items", not "done")

1. **Mirror-only build (CTL-002)** — this build used live egress: PyPI,
   CentOS Stream repos, github.com, quay.io (builder pod needs
   `dnsPolicy: Default`; cluster DNS wildcards external names into Traefik —
   itself a finding worth knowing). Release builds need mirrored
   pip/dnf/git sources; the spike deliberately did not build that mirror.
2. **Gateway path** — the cycle ran against the controller service directly;
   the gateway-fronted path (CTL-011: injected cookie, ROPC, `/api/controller/v2`)
   is untested against devel. The trusted-header auth class loading cleanly
   is a good sign, not proof.
3. `awx_plugins.interfaces` was installed at tip; pin it in the next build.
4. Migration-from-24.6.1 (CTL-013) untouched — this was an empty-database
   boot, which is the easy half.

## Cost of the whole spike

One session: ~15 min build on the shared builder, one scratch namespace
(deleted), zero impact on the running stacks.
