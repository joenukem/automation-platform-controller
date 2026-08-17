#!/usr/bin/env bash
# CTL-013/§9.1 — generate the controller+gateway runtime secrets FROM SCRATCH,
# with no dependency on prod1's live `automation-platform` namespace. This is
# what makes a clean-room (throwaway ci-k3s-vm) deploy self-contained: up.sh
# clones secrets from the live stack; up-cleanroom.sh calls this instead.
#
#   NS=ctl-cleanroom BASE_DOMAIN=cleanroom.local ADMIN_PASSWORD=... \
#     deploy/scratch/gen-secrets.sh | kubectl apply -f -
#
# Emits a multi-doc YAML of the five Secrets the stack consumes. Internal
# couplings handled here: the gateway postgres password appears both as
# `postgres-password` and inside `database-url`; `trusted-header-signing-secret`
# is a single value both the gateway and the controller read from this one
# secret. Dex is NOT required for the P0 password-grant path (the gateway signs
# its own tokens; JWKS fetch is lazy) — a self-signed dex TLS cert is still
# emitted so the gateway can mount it.
set -euo pipefail
NS="${NS:-ctl-cleanroom}"
BASE_DOMAIN="${BASE_DOMAIN:-cleanroom.local}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-cleanroom-admin}"

rand() { openssl rand -hex "${1:-16}"; }              # hex secret, n bytes
b64()  { base64 -w0; }

SECRET_KEY=$(openssl rand -base64 48 | tr -d '\n=+/' | cut -c1-50)
CTL_PG=$(rand 18)
GW_PG=$(rand 18)
GW_OIDC_SECRET=$(rand 24)
GW_SESSION=$(rand 24)
GW_TRUSTED=$(rand 24)
KEY_ID=$(rand 8)

# RSA signing key (PKCS#8 PEM) for the gateway's own JWT issuance.
SIGNING_KEY=$(openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>/dev/null)  # PKCS#8 by default

# Self-signed dex TLS (CA + server cert, SAN dex.<domain>).
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/ca.key" -out "$TMP/ca.crt" -subj "/CN=cleanroom-ca" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout "$TMP/tls.key" -out "$TMP/tls.csr" \
  -subj "/CN=dex.${BASE_DOMAIN}" >/dev/null 2>&1
openssl x509 -req -in "$TMP/tls.csr" -CA "$TMP/ca.crt" -CAkey "$TMP/ca.key" \
  -CAcreateserial -days 3650 -out "$TMP/tls.crt" \
  -extfile <(printf 'subjectAltName=DNS:dex.%s\n' "$BASE_DOMAIN") >/dev/null 2>&1

# admin password_hash in the gateway's exact format:
# pbkdf2-sha256:<iters>:<RawStdBase64 salt>:<RawStdBase64 key>  (16B salt, 32B key)
PW_HASH=$(python3 - "$ADMIN_PASSWORD" <<'PY'
import sys, os, hashlib, base64
pw = sys.argv[1].encode()
salt = os.urandom(16); iters = 210000
key = hashlib.pbkdf2_hmac('sha256', pw, salt, iters, 32)
raw = lambda b: base64.b64encode(b).rstrip(b'=').decode()
print(f"pbkdf2-sha256:{iters}:{raw(salt)}:{raw(key)}")
PY
)
USERS_JSON=$(cat <<JSON
{"users":[{"id":"u-admin","username":"admin","email":"admin@${BASE_DOMAIN}","password_hash":"${PW_HASH}","groups":["admins","system-administrators"],"scopes":["openid","profile","email","controller:read","controller:write","controller:admin","hub:read","hub:write"]}]}
JSON
)
DB_URL="postgres://awx_gateway:${GW_PG}@awx-gateway-postgres:5432/awx_gateway?sslmode=disable"

emit() { # name  then key=value pairs on stdin as `k\tv`
  echo "---"
  echo "apiVersion: v1"; echo "kind: Secret"; echo "metadata:"
  echo "  name: $1"; echo "  namespace: $NS"; echo "type: Opaque"; echo "data:"
  while IFS=$'\t' read -r k v; do [ -n "$k" ] && printf '  %s: %s\n' "$k" "$(printf '%s' "$v" | b64)"; done
}

emit awx-controller-runtime <<EOF
secret-key	$SECRET_KEY
postgres-password	$CTL_PG
EOF

emit awx-gateway-runtime <<EOF
postgres-password	$GW_PG
database-url	$DB_URL
gateway-oidc-client-secret	$GW_OIDC_SECRET
session-cookie-secret	$GW_SESSION
trusted-header-signing-secret	$GW_TRUSTED
EOF

# signing-key is a multiline PEM — base64 it directly (line-based emit mangles it)
echo "---"; echo "apiVersion: v1"; echo "kind: Secret"
echo "metadata: {name: awx-gateway-signing-key, namespace: $NS}"; echo "type: Opaque"; echo "data:"
printf '  key-id: %s\n' "$(printf '%s' "$KEY_ID" | b64)"
printf '  signing-key: %s\n' "$(printf '%s\n' "$SIGNING_KEY" | b64)"

# dex TLS (multiline PEMs — emit via files)
echo "---"; echo "apiVersion: v1"; echo "kind: Secret"
echo "metadata: {name: awx-dex-tls-secret, namespace: $NS}"; echo "type: kubernetes.io/tls"; echo "data:"
printf '  tls.crt: %s\n' "$(b64 < "$TMP/tls.crt")"
printf '  tls.key: %s\n' "$(b64 < "$TMP/tls.key")"
printf '  ca.crt: %s\n'  "$(b64 < "$TMP/ca.crt")"

emit awx-gateway-local-users <<EOF
users.json	$USERS_JSON
EOF
