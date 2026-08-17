# ADR-0002 — API tokens are gateway-issued; the controller consumes, never mints

Status: IMPLEMENTED (end-to-end proven) · 2026-08-17 · Drives the CTL-030 token row and the
`tokens` delta in `docs/api-surface.lock` (triaged in phase1/REPORT.md).

## Context

- The devel line removed the controller's OAuth2 provider — `/api/v2/tokens/`
  and `/api/v2/applications/` are gone. Verified twice in production form:
  the surface replay 404, and pool-manager's stored `awx-token` failing at
  cutover (rotated to Basic).
- The platform gateway (`awx-gateway`) already runs a full OAuth manager:
  token endpoint, client registry, signing keys, scoped access tokens; the
  controller already consumes gateway identity via the signed trusted header
  and DAB JWT (`AwxJWTAuthentication` is first in the auth classes).
- This matches the AAP 2.5+ product architecture (ledger: authenticators are
  GATEWAY), so it is parity-correct, not a workaround.

## Decision

1. **The gateway is the only token mint.** Personal/service access tokens
   come from the gateway's OAuth token endpoint; the controller never grows a
   token store again.
2. **The controller accepts gateway bearers everywhere Basic works.** DAB
   JWT consumption is the mechanism; any gap found where a gateway bearer
   fails but Basic succeeds is a defect against this ADR.
3. **Machine identities (pool-manager, telemetry) use Basic against the
   controller or gateway-minted service tokens** — never long-lived stored
   controller tokens (the class the cutover just retired).
4. **Lab-facing contract:** `connection-env.sh` exposes the gateway token
   endpoint as `CONTROLLER_TOKEN_URL`; ex467-13 ("automate via the API")
   teaches minting a token at the gateway and calling the controller with
   the bearer — which is exactly how AAP 2.5+ behaves.

## Consequences

- `docs/api-surface.lock`'s `tokens` row moves from ALLOW_MISSING to a
  gateway-path entry once the lab is reworked.
- ex467-13's seed and steps need the token-URL rework (lab-content change,
  scheduled with the Phase-2 lab sweep).
- The gateway Basic→local-users quirk found in Phase 1 becomes more
  important (it is on the token-mint path for local identities) and should
  be fixed in `awx-gateway` alongside this.

## Acceptance

- Surface replay: gateway token endpoint mints a token for a Keycloak lab
  user; `curl -H "Authorization: Bearer …" $CONTROLLER/api/v2/me/` returns
  that user. Wired into `build/verify.sh`.
- ex467-13 green in the DO467 suite using the new flow.

## Implementation status (2026-08-17)

**Gateway password grant: SHIPPED** (awx-gateway `ffe0a41d`). `/oauth2/token`
now accepts `grant_type=password`, verifying credentials through the same
finalized identity chain as interactive login (local users, then OIDC ROPC).
Proven live: a Keycloak lab user (in `lab-temporary-users`, so carrying
`controller:*` scopes) exchanges username+password for a well-formed access
token — decoded and confirmed `aud=controller`, correct scopes, correct sub.

**Bearer acceptance on the proxied controller path: FIXED and proven**
(awx-gateway `cbf39e52`). The rejection was a latent gateway bug the password
grant surfaced: `LookupAccessToken` required the stored record's UserID to
equal the JWT `sub`, but the SQL store keys tokens on an internal `users.id`
(upserted by username) while the JWT `sub` carries the external identity id —
two id spaces that never match, so EVERY SQL-store bearer was rejected. It
went unnoticed because the console authenticates with session cookies, not
bearer tokens; the ROPC grant was the first path to present a bearer to the
proxy. Removed the id-equality clause (authenticity still comes from the
verified JWT signature/claims and the unrevoked stored token hash; client_id
and scopes are still checked). Proven live: `probe-kc` mints a password-grant
token and calls the controller `/api/v2/me/` and `/ping/` through the gateway
— 200, correct user. ex467-13's rework is now unblocked.

The pull-policy detail worth keeping: the OAP gateway deployment runs
`imagePullPolicy: Never` (node-local images) — a registry-tagged overlay
needs the policy flipped to `IfNotPresent` to roll.

