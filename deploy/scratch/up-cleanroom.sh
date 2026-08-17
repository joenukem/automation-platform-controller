#!/usr/bin/env bash
# §9.1 — SELF-CONTAINED clean-room bring-up. Unlike up.sh (which clones five
# secrets from prod1's live automation-platform namespace), this generates every
# secret from scratch via gen-secrets.sh, so it works on a throwaway cluster
# (ci-k3s-vm) with no prod1 dependency. Postgres uses emptyDir (no storageclass
# needed); dex is not deployed (P0 auth is the gateway's password grant, whose
# tokens the gateway signs itself — JWKS fetch is lazy).
#
#   NS=ctl-cleanroom BASE_DOMAIN=cleanroom.local \
#     CTL_IMAGE=franken-registry.example.com:5000/automation-platform/controller:airgap-v8 \
#     deploy/scratch/up-cleanroom.sh
set -euo pipefail
NS="${NS:-ctl-cleanroom}"
BASE_DOMAIN="${BASE_DOMAIN:-cleanroom.local}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-cleanroom-admin}"
CTL_IMAGE="${CTL_IMAGE:-franken-registry.example.com:5000/automation-platform/controller:airgap-v8}"
# ROPC gateway: the tag with the ADR-0002 password-grant/local-users identity
# provider. The stock gateway.yaml pins an older tag without it.
GW_IMAGE="${GW_IMAGE:-franken-registry.example.com:5000/awx-gateway:ropc-pw-117b9305}"
SEED_USERS="${SEED_USERS:-bob alice}"   # lab users the provider specs reference
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/labpool-prod1-k3s.yaml}"
here="$(cd "$(dirname "$0")" && pwd)"

kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"

echo "== generating self-contained secrets"
NS="$NS" BASE_DOMAIN="$BASE_DOMAIN" ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  bash "$here/gen-secrets.sh" | kubectl apply -f -

echo "== applying stack + gateway (ns=$NS, controller image=$CTL_IMAGE)"
sed -e "s/namespace: ctl-phase1/namespace: $NS/" \
    -e "s#automation-platform/controller:0.0.1-phase0#${CTL_IMAGE#*/}#g" \
    "$here/stack.yaml" | kubectl apply -f -
sed -e "s/namespace: ctl-phase1/namespace: $NS/" \
    -e "s#awx-gateway:0.1.0-aap4#${GW_IMAGE#*/}#g" \
    "$here/gateway.yaml" | kubectl apply -f -

echo "== waiting for rollout"
kubectl -n "$NS" rollout status deploy/awx-controller-postgres --timeout=300s
kubectl -n "$NS" wait --for=condition=complete job/awx-controller-migrate --timeout=900s
kubectl -n "$NS" rollout status deploy/awx-controller-web deploy/awx-controller-task --timeout=600s
kubectl -n "$NS" rollout status deploy/awx-gateway --timeout=300s || true

echo "== bootstrapping controller superuser"
T=$(kubectl -n "$NS" get pods --no-headers -o custom-columns=N:.metadata.name | grep controller-task | head -1)
kubectl -n "$NS" exec "$T" -c awx-task -- bash -c \
  "awx-manage createsuperuser --username admin --email admin@${BASE_DOMAIN} --noinput 2>/dev/null; \
   awx-manage update_password --username admin --password ${ADMIN_PASSWORD} >/dev/null; \
   awx-manage register_default_execution_environments >/dev/null 2>&1; echo bootstrap-ok"

echo "== seeding lab users ($SEED_USERS) referenced by provider specs"
for u in $SEED_USERS; do
  kubectl -n "$NS" exec "$T" -c awx-task -- bash -c \
    "awx-manage shell_plus -c \"from django.contrib.auth import get_user_model as g; U=g(); U.objects.filter(username='$u').exists() or U.objects.create_user('$u','$u@${BASE_DOMAIN}','cleanroom-$u')\"" >/dev/null 2>&1 \
    && echo "  seeded $u" || echo "  (skip $u)"
done

echo "== ping"
kubectl -n "$NS" exec "$T" -c awx-task -- curl -s -m 10 http://awx-controller:8052/api/v2/ping/ | head -c 200; echo
echo "== clean-room up in ns=$NS"
