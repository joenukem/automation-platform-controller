#!/usr/bin/env bash
# Production resource sizing for the controller, derived empirically from the
# CTL-050 soak (reports/ctl-050-soak.md). The deploy/scratch manifests ship a
# small profile (web 1 CPU / 1 replica, postgres 500m, task 2Gi) that is correct
# for functional tests but does NOT meet the 10-concurrent-session SLO
# (list p95 <=2s @ 10k jobs, no 5xx). Apply this to a deployment namespace to
# reach the sizing that measured list p95 0.89s / prov p95 2.4s / 0 5xx / stable
# task tier under the 2h soak.
#
#   NS=automation-platform deploy/apply-production-sizing.sh
#
# Idempotent (kubectl set resources / scale). Values, per the soak's scaling
# curve — raise further only if a run shows a tier still saturated:
#   web:      3 replicas x 4 CPU        (list serialization is CPU-bound)
#   postgres: 4 CPU / 2Gi               (list reads + provisioning writes)
#   task:     awx-task 6Gi              (org-deletion reaper working set at 10x)
set -euo pipefail
NS="${NS:-automation-platform}"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/labpool-prod1-k3s.yaml}"

echo "== sizing controller in ns=$NS for the 10-session SLO"
kubectl -n "$NS" scale deploy/awx-controller-web --replicas="${WEB_REPLICAS:-3}"
kubectl -n "$NS" set resources deploy/awx-controller-web -c awx-web \
  --requests=cpu=500m,memory=512Mi --limits=cpu="${WEB_CPU:-4}",memory=2Gi
kubectl -n "$NS" set resources deploy/awx-controller-postgres -c postgres \
  --requests=cpu=500m,memory=512Mi --limits=cpu="${PG_CPU:-4}",memory=2Gi
kubectl -n "$NS" set resources deploy/awx-controller-task -c awx-task \
  --requests=cpu=500m,memory=1Gi --limits=cpu=2,memory="${TASK_MEM:-6Gi}"

kubectl -n "$NS" rollout status deploy/awx-controller-web --timeout=300s
kubectl -n "$NS" rollout status deploy/awx-controller-postgres --timeout=300s
kubectl -n "$NS" rollout status deploy/awx-controller-task --timeout=300s
echo "== sized. Re-run build/soak.py against this ns to confirm the SLO."
echo "   NOTE: deploy/scratch postgres uses emptyDir — a resource change RESTARTS"
echo "   it and WIPES the DB. For a persistent stack, back postgres with a PVC first."
