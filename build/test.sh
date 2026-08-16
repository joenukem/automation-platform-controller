#!/usr/bin/env bash
# Regression tripwire: run upstream's unit test subset inside the built image.
#
#   build/test.sh [tag]     # defaults to work/last-build-tag
#
# Runs a pod from the image on prod1 (dnsPolicy Default so pip can fetch
# pytest), installs the test tooling into the image's own venv, and runs the
# no-database unit subset. The pass/fail counts are the baseline every patch
# is judged against — a patch that changes them must say why.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/labpool-prod1-k3s.yaml}"
TAG="${1:-$(cat "$here/work/last-build-tag" 2>/dev/null)}"
[ -n "$TAG" ] || { echo "no tag; run build/build.sh first" >&2; exit 1; }
IMG="franken-registry.example.com:5000/automation-platform/controller:$TAG"
POD="ctl-unit-$(echo "$TAG" | tr -cd 'a-z0-9' | tail -c 8)"

kubectl -n image-build delete pod "$POD" --ignore-not-found >/dev/null
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata: {name: $POD, namespace: image-build}
spec:
  restartPolicy: Never
  dnsPolicy: Default
  containers:
  - name: t
    image: $IMG
    command: ["sleep", "7200"]
    securityContext: {runAsUser: 0}
EOF
kubectl -n image-build wait --for=condition=Ready pod/$POD --timeout=600s >/dev/null
mkdir -p "$here/reports"
kubectl -n image-build exec $POD -- bash -c '
  set -e
  VENV=/var/lib/awx/venv/awx
  $VENV/bin/pip install -q pytest pytest-django pytest-mock 2>&1 | tail -1 || true
  AWX_PKG=$($VENV/bin/python -c "import awx, os; print(os.path.dirname(awx.__file__))")
  cd "$AWX_PKG"
  DJANGO_SETTINGS_MODULE=awx.settings $VENV/bin/pytest -q -p no:cacheprovider \
    main/tests/unit 2>&1 | tail -15
' | tee "$here/reports/pytest-unit-$TAG.txt"
kubectl -n image-build delete pod "$POD" --wait=false >/dev/null
echo "== report: reports/pytest-unit-$TAG.txt"
