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
# The sdist install excludes tests: run them from the (patched) SOURCE tree
# with the image venv, source first on the path so patched code is what runs.
[ -d "$here/work/build/awx" ] || { echo "no work/build/awx tree; run build/build.sh first" >&2; exit 1; }
tar -C "$here/work/build/awx" -czf "$here/work/testsrc.tgz" --exclude=.git awx requirements pytest.ini setup.cfg pyproject.toml
kubectl cp "$here/work/testsrc.tgz" image-build/$POD:/tmp/testsrc.tgz
kubectl -n image-build exec $POD -- bash -c '
  set -e
  VENV=/var/lib/awx/venv/awx
  true
  mkdir -p /srv/testsrc && cd /srv/testsrc && tar xzf /tmp/testsrc.tgz
  # upstream own dev/test dependency set — no cherry-picking
  $VENV/bin/pip install -q -r requirements/requirements_dev.txt 2>&1 | tail -2 || true
  # CI settings shim: upstream test settings + plain logging. The default
  # LOGGING wires filters/handlers that assume a full tower runtime; a test
  # pod is not one, and the harness owns its own logging.
  cat > /srv/testsrc/test_settings_ci.py <<PYSET
from awx.main.tests.settings_for_test import *  # noqa
LOGGING = {"version": 1, "disable_existing_loggers": False,
           "handlers": {"console": {"class": "logging.StreamHandler"}},
           "root": {"handlers": ["console"], "level": "WARNING"}}
# strip dev-only apps/middleware that the runtime image does not carry
def _importable(mod):
    import importlib.util
    return importlib.util.find_spec(mod.split(".")[0]) is not None
INSTALLED_APPS = [a for a in INSTALLED_APPS if _importable(a)]  # noqa
MIDDLEWARE = [m for m in MIDDLEWARE if _importable(m)]  # noqa
PYSET
  PYTHONPATH=/srv/testsrc DJANGO_SETTINGS_MODULE=test_settings_ci \
    $VENV/bin/pytest -q -p no:cacheprovider --tb=no awx/main/tests/unit 2>&1 | tail -12
' | tee "$here/reports/pytest-unit-$TAG.txt"
kubectl -n image-build delete pod "$POD" --wait=false >/dev/null
echo "== report: reports/pytest-unit-$TAG.txt"
