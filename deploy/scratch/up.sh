#!/usr/bin/env bash
# Bring up the composed controller in a scratch namespace on prod1.
# Clones the two runtime secrets from the live stack (SECRET_KEY, DB creds,
# gateway keys) — scratch shares the lab credential universe by design.
set -euo pipefail
NS="${NS:-ctl-phase1}"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/labpool-prod1-k3s.yaml}"
here="$(cd "$(dirname "$0")" && pwd)"
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"
for s in awx-controller-runtime awx-gateway-runtime awx-dex-tls-secret awx-gateway-local-users awx-gateway-signing-key; do
  kubectl -n automation-platform get secret "$s" -o json \
   | python3 -c "import json,sys;d=json.load(sys.stdin);[d['metadata'].pop(k,None) for k in ('namespace','resourceVersion','uid','creationTimestamp','ownerReferences','managedFields','annotations','labels')];d['metadata']['namespace']='$NS';print(json.dumps(d))" \
   | kubectl apply -f -
done
sed "s/namespace: ctl-phase1/namespace: $NS/" "$here/stack.yaml" | kubectl apply -f -
sed "s/namespace: ctl-phase1/namespace: $NS/" "$here/gateway.yaml" | kubectl apply -f -
kubectl -n "$NS" rollout status deploy/awx-controller-postgres --timeout=300s
kubectl -n "$NS" wait --for=condition=complete job/awx-controller-migrate --timeout=900s
kubectl -n "$NS" rollout status deploy/awx-controller-web deploy/awx-controller-task --timeout=600s
T=$(kubectl -n "$NS" get pods --no-headers -o custom-columns=N:.metadata.name | grep controller-task | head -1)
kubectl -n "$NS" exec "$T" -c awx-task -- bash -c \
  'awx-manage createsuperuser --username admin --email admin@example.com --noinput 2>/dev/null; \
   awx-manage update_password --username admin --password phase0-admin >/dev/null; \
   awx-manage register_default_execution_environments >/dev/null; echo bootstrap-ok'
kubectl -n "$NS" exec "$T" -c awx-task -- curl -s -m 10 http://awx-controller:8052/api/v2/ping/ | head -c 200; echo
