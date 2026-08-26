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

What has been verified:

- `git apply --check` of the patch against `sources.lock` awx `3fea0704` — clean.
- The vendored subsystem's completeness, as tabulated above, read from
  `upstream/django-ansible-base` at the pinned SHA.
- The automatic settings and URL wiring, read from `settings_logic.py:147` and
  `dynamic_urls.py`.

What has **not** been verified, and must be before this is called done:

- No image has been rebuilt. `build/build.sh` and `build/airgap-build.sh` have not
  been run with this patch in the series.
- No migrations have been applied and no `manage.py check` has been run against a
  build with the app enabled.
- No authenticator has been created or logged in with. Per the repo's standard,
  a type is not supported until a real directory or IdP authenticates a real user
  and the maps materialize the expected privilege — canned fixtures are not
  evidence.
