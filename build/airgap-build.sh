#!/usr/bin/env bash
# CTL-002 — egress-free release build. Builds the controller image with ZERO
# network from the captured vendor bundle, proving a disconnected release path.
#
#   build/airgap-build.sh [tag]        # default tag: airgap-<inputhash>
#
# Prereq: the vendor bundle for the current sources.lock must exist:
#   buildah bud -f build/vendor/Dockerfile.capture \
#     --build-arg MIRROR_BASE=$REG_PUSH/mirror \
#     -t $REG_PUSH/automation-platform/vendor-capture:full .    # egress allowed
# Re-run that capture at every sources.lock bump (see STEWARDSHIP.md).
#
# This script then: renders the Dockerfile in VENDORED mode (offline dnf+pip,
# exact-pinned requirements_local.txt from the bundle wheel list), and builds
# with `buildah bud --network none --pull=never` — no RUN step has any network.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/labpool-prod1-k3s.yaml}"
REG_PUSH="${REG_PUSH:-192.168.1.240:30500}"
MIRROR_BASE="${MIRROR_BASE:-$REG_PUSH/mirror}"
VENDOR_IMAGE="${VENDOR_IMAGE:-$REG_PUSH/automation-platform/vendor-capture:full}"
IMG="automation-platform/controller"
WORK="${WORK:-$here/work/build}"
NS=image-build; BUILDER=ctl-dev-bld

INPUT_HASH=$(cat "$here/sources.lock" "$here/build/render_dockerfile.py" \
                 $(ls "$here"/patches/*.patch 2>/dev/null) 2>/dev/null | sha256sum | cut -c1-10)
TAG="${1:-airgap-g${INPUT_HASH}}"
echo "== airgap build ${IMG}:${TAG} (bundle ${VENDOR_IMAGE})"

# The patched source tree is produced by a prior build/build.sh run (clone +
# patch queue). Reuse it; the airgap build only re-renders + rebuilds offline.
if [ ! -d "$WORK/awx/.git" ]; then
  echo "!! no patched source tree at $WORK/awx — run build/build.sh once first" >&2
  exit 1
fi
git -C "$WORK/awx" checkout -q -- . 2>/dev/null || true
git -C "$WORK/awx" clean -qfd 2>/dev/null || true   # disposable clone: full reset
while IFS= read -r p; do
  [ -n "$p" ] && [ "${p:0:1}" != "#" ] || continue
  git -C "$WORK/awx" apply "$here/patches/$p" 2>/dev/null || true
done < "$here/patches/series"

# Ensure the builder pod is up (it owns the local bundle + base images).
kubectl -n $NS get pod $BUILDER >/dev/null 2>&1 || { echo "builder pod $BUILDER absent; run build/build.sh" >&2; exit 1; }
kubectl -n $NS wait --for=condition=Ready pod/$BUILDER --timeout=120s >/dev/null

# Derive the exact bundle wheel list so requirements_local.txt pins match.
WHEELS=$(kubectl -n $NS exec $BUILDER -- sh -c \
  'buildah from --name _wl '"$VENDOR_IMAGE"' >/dev/null 2>&1; buildah run _wl -- sh -c "ls /vendor/wheels" 2>/dev/null; buildah rm _wl >/dev/null 2>&1')
[ -n "$WHEELS" ] || { echo "empty bundle wheel list — is $VENDOR_IMAGE built?" >&2; exit 1; }

MIRROR_BASE="$MIRROR_BASE" VENDORED=1 VENDOR_IMAGE="$VENDOR_IMAGE" VENDOR_WHEEL_LIST="$WHEELS" \
  python3 "$here/build/render_dockerfile.py" "$WORK/awx"

CTX="$WORK/airgap-ctx.tgz"
tar -C "$WORK/awx" -czf "$CTX" --exclude=.git .
kubectl -n $NS exec $BUILDER -- sh -c 'rm -rf /work/airgap && mkdir -p /work/airgap'
kubectl cp "$CTX" $NS/$BUILDER:/work/airgap/ctx.tgz
kubectl -n $NS exec $BUILDER -- sh -c "cd /work/airgap && tar xzf ctx.tgz && \
  buildah bud --format docker --tls-verify=false --pull=never --network none \
    --build-arg VERSION=25.0.0.dev0 --build-arg SETUPTOOLS_SCM_PRETEND_VERSION=25.0.0.dev0 \
    -t $REG_PUSH/$IMG:$TAG . 2>&1 | tail -3 && \
  buildah push --tls-verify=false $REG_PUSH/$IMG:$TAG 2>&1 | tail -1"
echo "== airgap image pushed: $REG_PUSH/$IMG:$TAG"
echo "   verify functional parity: build/test.sh $TAG   (expect baseline 1233 pass)"
