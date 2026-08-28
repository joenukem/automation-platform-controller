# ADR-0003 — the platform authenticator subsystem is `ansible_base.authentication`, enabled in this build

Status: ACCEPTED · 2026-08-26 · Implemented by `patches/0013-enable-dab-authentication.patch`
Supersedes the `Platform authenticators` row in [PARITY-LEDGER.md](PARITY-LEDGER.md).
Qualifies [ADR-0002](ADR-0002-gateway-issued-tokens.md).

## Context

`django-ansible-base` is pinned in `sources.lock` and vendored under
`upstream/django-ansible-base`. Its `ansible_base/authentication/` package is the
authenticator subsystem the AAP platform gateway is built from, and it is
complete in the tree we already ship:

| | Vendored at `f90ed8a` |
| --- | --- |
| Authenticator plugins | 15 — `local`, `ldap`, `saml`, `oidc`, `keycloak`, `azuread`, `google_oauth2`, `github`, `github_org`, `github_team`, `github_enterprise`, `github_enterprise_org`, `github_enterprise_team`, `radius`, `tacacs` |
| Models | `authenticator`, `authenticator_map`, `authenticator_user` |
| Map types | all five — `allow`, `is_superuser`, `role`, `organization`, `team` |
| Triggers | full `TRIGGER_DEFINITION` — `always`, `never`, `groups` (`has_or`/`has_and`/`has_not`), `attributes` (`join_condition` + `contains`/`matches`/`ends_with`/`equals`/`in`) |
| Views | `authenticator`, `authenticator_map`, `authenticator_plugins`, `authenticator_users`, `trigger_definition`, `ui_auth` |
| Migrations | 18 |

**It was not in `INSTALLED_APPS`.** The build enabled six DAB apps —
`rest_filters`, `jwt_consumer`, `resource_registry`, `rbac`, `feature_flags`,
`api_documentation` — and not `authentication`. The whole subsystem shipped in
the image as unreachable code, and the `authentication` extra was absent from the
DAB pin, so its dependencies were not installed either.

The cost of that omission was being paid elsewhere. A parallel implementation of
the same resource model was being written in Go in `awx-gateway`
(`internal/authenticator/`, PRs 250 and 254) — LDAP bind, authenticator CRUD,
authenticator maps, the trigger grammar — reaching roughly one authenticator
type, three of five map types, and no plugin-schema or trigger-definition
discovery, against a Python implementation sitting in this repo with upstream
tests behind it.

## Decision

**Enable `ansible_base.authentication` in this build.** The platform authenticator
subsystem is the upstream one; we configure it, we do not reimplement it.

Three changes, all required together
(`patches/0013-enable-dab-authentication.patch`):

1. `'ansible_base.authentication'` in `INSTALLED_APPS`.
2. The `authentication` extra on the `django-ansible-base` pin in
   `requirements/requirements_git.txt`.
3. `openldap-devel` + `cyrus-sasl-devel` in the builder stage and `openldap` in
   the runtime stage of `Dockerfile.j2`.

Nothing else is needed, and that is the point of the decision — the wiring is
already there:

- `ansible_base.lib.dynamic_config.settings_logic` branches on this app being
  installed (`settings_logic.py:147`) and appends the `AnsibleBaseAuth` backend,
  inserts `SocialExceptionHandlerMiddleware` and `AuthenticatorBackendMiddleware`
  ahead of `django.contrib.auth`'s `AuthenticationMiddleware`, and prepends DAB's
  `SessionAuthentication` to DRF.
- `dynamic_urls` walks `INSTALLED_APPS` for `ansible_base.*` apps exposing
  `urls.py` and collects their `api_urls` / `api_version_urls` / `root_urls`;
  `awx/urls.py` already imports and mounts all three.

Item 3 is the only non-obvious one. `python-ldap` is sdist-only on PyPI so it
compiles at install time, and upstream removed the OpenLDAP headers from the
builder image when authentication moved out of the controller. `swig` and
`xmlsec1-devel` are still present and cover `python3-saml`, which is why SAML
needs no build change and LDAP does.

## Relationship to ADR-0002

ADR-0002 says the gateway is the only token mint, and the `Platform
authenticators` row in PARITY-LEDGER.md assigns authenticators to
`awx-gateway` on the grounds that AAP 2.5+ moved authentication to the gateway.

That reading is correct about the product and was the right call for *tokens*.
It is the wrong conclusion for *this code*, for a reason worth stating plainly:
in AAP, "the gateway owns authentication" is a statement about which service
enables `ansible_base.authentication` — not about the subsystem being something
other than DAB. Enabling the app here does not contradict ADR-0002's token
decision, which stands unchanged: the controller still mints no tokens and still
consumes gateway identity via `AwxJWTAuthentication`.

**The tension this leaves open, honestly stated:** with the app enabled here, this
service can terminate authentication directly, which is a different topology from
AAP's. If a separate platform-gateway service is later stood up, it should be the
one enabling this app, and this build should go back to consuming its identity.
The change is a settings line and an extra either way — which is the practical
argument for taking the upstream implementation now rather than growing a second
one in Go.

## Consequences

- The `Platform authenticators` PARITY-LEDGER row moves from `GATEWAY`
  (`awx-gateway` owns) to `IN-1.0`, satisfied by upstream code.
- 18 authentication migrations must be applied. Existing deployments need a
  migration run, not just an image roll.
- The image grows by the `authentication` extra: `social-auth-core`,
  `social-auth-app-django`, `django-auth-ldap`, `python-ldap`, `ldap-filter`,
  `python3-saml`, `tacacs_plus`, `pyrad`, `xmlsec`, `lxml`, `tabulate`.
- The vendored-wheel bundle must be re-captured **once with egress allowed**
  (`build/vendor/Dockerfile.capture`, updated alongside this patch to install the
  OpenLDAP/xmlsec headers at capture time and to pull `openldap-devel`,
  `openldap-clients` and `cyrus-sasl-devel` into the RPM closure) before an
  egress-free `build/airgap-build.sh` can resolve the new dependencies.
- The Go authenticator implementation in `awx-gateway` (`internal/authenticator/`)
  is superseded as a parity target. It is still what the currently deployed
  gateway runs, so it should be retired deliberately rather than deleted.

## Status of verification

Built and verified on **franken** (`image-build` namespace), 2026-08-27, image
`automation-platform/controller:0.0.2-g632780bc3a`. Two lanes: lane A built the
image and ran the unit tripwire; lane B proved the dependency set independently
on the previous image.

| Check | Result |
| --- | --- |
| Patch applies to `sources.lock` awx `3fea0704` | clean, 4 files |
| Image builds with the added LDAP/SAML build deps | **pass** — pushed `0.0.2-g632780bc3a` |
| `python-ldap` compiles against `openldap-devel` | **pass** — 3.4.7 in the image venv |
| All 7 auth deps baked into the image venv | **pass** — 7/7 |
| Third-party imports (lane B: ldap, django_auth_ldap, onelogin.saml2, xmlsec, lxml, tacacs_plus, pyrad, 4× social_core, social_django, tabulate) | **pass** — 14/14 |
| `'ansible_base.authentication'` in the shipped settings | **pass** |
| `awx-manage check` | **pass** — only the pre-existing headless `staticfiles.W004` |
| `AnsibleBaseAuth` appended to `AUTHENTICATION_BACKENDS` | **pass** |
| `SocialExceptionHandlerMiddleware` + `AuthenticatorBackendMiddleware` present | **pass** |
| DAB middleware ordered **before** `django.contrib.auth`'s | **pass** — index 11 vs 12 |
| DAB `SessionAuthentication` first in DRF `DEFAULT_AUTHENTICATION_CLASSES` | **pass** |
| Routes mounted | **pass** — `authenticators` (7), `authenticator_maps` (6), `authenticator_plugins`, `trigger_definition`, `ui_auth` |
| Model drift (`makemigrations --check`) | **pass** — "No changes detected in app 'dab_authentication'" |
| Unit tripwire vs last good run | **pass** — `13 failed, 1235 passed, 1 xfailed, 116 errors`, identical failure set to `g1cd28c7d49` |

### The one real defect this found

The first build (`0.0.2-gcffb0f7384`) **broke the entire unit suite at collection**.
`pytest.ini` sets `filterwarnings = error`, and DAB's `AuthenticatorMap.Meta`
builds its two `CheckConstraint`s with the deprecated `check=` kwarg, so importing
`ansible_base.authentication.models.authenticator_map` raised
`RemovedInDjango60Warning` — not one failing test, but zero tests collected.

Fixed in the patch by a narrow `ignore:CheckConstraint.check is deprecated` entry,
following the file's existing precedent for the DAB `UnorderedObjectListWarning`.
Verified in isolation before rebuilding: the import raises under `-W error` and
succeeds with the filter. Delete the entry when upstream moves to `condition=`.

### Routes land on `/api/v2/`, not a gateway path

Worth recording because it makes the topology question concrete rather than
theoretical: with the app enabled here the endpoints are
`/api/v2/authenticators/`, `/api/v2/authenticator_plugins/`,
`/api/v2/trigger_definition/`, `/api/v2/ui_auth/` — the controller's own API
namespace. `docs/api-surface.lock` is unchanged and correctly so: it records
endpoints a platform consumer actually calls, and nothing calls these yet, so
`build/verify.sh` is unaffected.

### Migration risk for existing deployments

18 migrations, and they are additive: 3 `CreateModel` for the app's own tables,
with every `AlterField`/`RemoveField`/`RenameField` being that app's own history
replayed on a fresh install. The only cross-app dependency is
`swappable_dependency(AUTH_USER_MODEL)` — foreign keys to the user table. No
existing AWX table is altered.

### Still outstanding

- Migrations have **not** been applied to a live database — `makemigrations
  --check` proves the models and migrations agree, not that a migrate run
  succeeds against an existing schema.
- **No authenticator has been created and no directory login performed.** Per the
  repo standard a type is not supported until a real directory or IdP
  authenticates a real user and the maps materialize the expected privilege.
  Everything above is build- and boot-level evidence.
