#!/usr/bin/env bash
# Conformance gate for a running controller (the release check for a build).
#
#   CONTROLLER_URL=http://127.0.0.1:18053 ADMIN_PASSWORD=... build/verify.sh
#
# 1. api-surface replay: every locked collection endpoint answers 200
#    (405 tolerated for POST-only endpoints; the known-triaged deltas are
#    listed in ALLOW_MISSING).
# 2. provider conformance: pool-manager's real Ensure/Delete path with a lab
#    spec, leak-scan clean (needs go + the pool-manager checkout).
# The DO467 serial subset (lab-content tools/ci_incluster.sh) is the third
# leg, run from lab-content because it needs the whole platform.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
: "${CONTROLLER_URL:?set CONTROLLER_URL}"
: "${ADMIN_PASSWORD:?set ADMIN_PASSWORD}"
ADMIN_USER="${ADMIN_USER:-admin}"
ALLOW_MISSING="openapi settings/ldap tokens"   # triaged in docs/phase1/REPORT.md
POSTONLY="schedules/preview"

fail=0
while IFS='|' read -r path _; do
  path=$(echo "$path" | xargs); [ -n "$path" ] || continue
  case "$path" in \#*|*':id'*) continue;; esac
  code=$(curl -sk -m 20 -u "$ADMIN_USER:$ADMIN_PASSWORD" -o /dev/null -w '%{http_code}' "$CONTROLLER_URL/api/v2/$path/")
  ok=false
  [ "$code" = 200 ] && ok=true
  case " $POSTONLY " in *" $path "*) [ "$code" = 405 ] && ok=true;; esac
  case " $ALLOW_MISSING " in *" $path "*) ok=true;; esac
  $ok || { echo "SURFACE FAIL $code $path"; fail=1; }
done < "$here/docs/api-surface.lock"
[ "$fail" = 0 ] && echo "surface replay: OK"

# ADR-0001 increment 3: the locked list endpoints must honor ?organization=
# scoping (scoped-by-default consumers depend on it).
for p in inventories projects job_templates workflow_job_templates; do
  code=$(curl -sk -m 20 -u "$ADMIN_USER:$ADMIN_PASSWORD" -o /dev/null -w '%{http_code}' "$CONTROLLER_URL/api/v2/$p/?organization=1&page_size=1")
  [ "$code" = 200 ] || { echo "ORG-FILTER FAIL $code $p"; fail=1; }
done
[ "$fail" = 0 ] && echo "organization-filter conformance: OK"

PM=/mnt/labpool/pool-manager
if command -v go >/dev/null && [ -d "$PM/cmd/provider-conformance" ]; then
  ( cd "$PM" && AWX_BASE_URL="$CONTROLLER_URL" AWX_USERNAME="$ADMIN_USER" AWX_PASSWORD="$ADMIN_PASSWORD" \
    GIT_CLONE_URL="${GIT_CLONE_URL:-http://gitea-http.gitea.svc:3000/labadmin/datacenter-playbooks.git}" \
    go run ./cmd/provider-conformance -spec "${CONFORMANCE_SPEC:-/mnt/labpool/lab-content/DO467/ex467-06-inventories-host-groups-vars/lab-content/labprovisioning-ex467-06-inventories-host-groups-vars.yaml}" ) \
    || fail=1
else
  echo "provider conformance: SKIPPED (go or pool-manager checkout missing)"
fi
exit $fail
