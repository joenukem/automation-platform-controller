# CTL-060 (P0) + CTL-061 (P1) — security acceptance

Date: 2026-08-17 · Harness: `build/ctl060_061_acceptance.sh` · Target: prod1
`automation-platform` controller `0.0.2-g1cd28c7d49` (live).

Negative checks are the executable spec (docs/design/DESIGN-AGENDA). The harness
runs entirely via `kubectl exec` into the controller web/task pods: ORM/serializer
proofs for the authorized-content claims (exactly what the API renders), curl for
the unauthenticated negatives. It creates only `CTL06x-*` objects and deletes them.

## Result: ALL CHECKS PASS

### CTL-060 (P0) — no default credentials, gateway identity, session isolation
- **[C1] No default credentials.** 10 default admin passwords (admin, password,
  AWX, awx, awxsecret, changeme, admin123, Password1, redhat, ansible) → **401**;
  default non-admin logins (root/superuser/operator/awx) → **401**.
- **[C2] Anonymous denied.** `GET /api/v2/me/` with no identity → **401**.
- **[C3] Forged gateway trusted-header rejected.** A request carrying an unsigned
  `X-DAB-JW-TOKEN` + `X-Trusted-Proxy` cannot impersonate → **401** (the controller
  trusts only the gateway's *signed* header).
- **[C4] No default-bootstrap env.** The task deployment carries no
  `AWX_ADMIN_PASSWORD` env — admin identity is gateway-group-driven
  (`AWX_GATEWAY_ADMIN_GROUPS`), not a shipped default.
- **[C5] Session isolation.** With two orgs + two non-superusers, `InventoryAccess`
  RBAC scoping proves userB (orgB) **cannot** see orgA's inventory, while userA
  (granted the inventory read role in orgA) **can** — org-scoped, superuser
  reserved for the platform.

Gateway-issued-identity round-trip (the positive path) and the org-filter surface
are additionally covered by `build/verify.sh` (§9.1).

### CTL-061 (P1) — redacted logging, webhook-key authorization
- **[L1] Secret field redaction.** A credential's `password` renders as
  `$encrypted$` in the API representation, is stored as `$encrypted$` ciphertext
  at rest, and the plaintext sentinel is absent from the serialized credential.
- **[L2] Redacted logging.** After a failed login that carries a unique sentinel
  as the password, the sentinel appears **0** times across the web + task logs
  (`/var/log/tower`, nginx, and pod stdout) at default verbosity.
- **[W1] Webhook key only via the authorized sub-endpoint.** `webhook_key` is
  **not a field** in the JobTemplate serializer (absent from the detail body);
  the raw key value is not present in the serialized JT data; and an
  **unauthorized** `GET /job_templates/<id>/webhook_key/` → **401**.

## Fix shipped with this acceptance: patch 0009

The [W1] unauthorized check initially returned **500**, not 401:
`WebhookKeyPermission` implemented only `has_object_permission`
(`request.user.can_access(...)`), so an anonymous request fell through to
`AnonymousUser.can_access` → `AttributeError` → 500. The key was never leaked
(the error precedes any response body), but 500 is the wrong contract for CTL-061.

**patch 0009** adds an authenticated-only `has_permission` to
`WebhookKeyPermission` (mirroring `IsSystemAdmin`/`IsSystemAdminOrAuditor`), so
anonymous callers get a clean **401**. Built into `0.0.2-g1cd28c7d49`, deployed to
prod1 + franken, and the acceptance re-run is green above. Unit tripwire on the
same image: 1235 passed / 13 failed / 116 errors — unchanged from baseline.
