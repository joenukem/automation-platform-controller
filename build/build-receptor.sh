#!/usr/bin/env bash
# Build and push the patched receptor sidecar image (see receptor/README.md).
#
#   SUFFIX=<tag-suffix> build/build-receptor.sh
#
# The Go compile happens here (a static CGO_ENABLED=0 binary); the image build
# happens in a buildah pod on the target cluster, which is the only thing that can
# reach the franken registry holding the awx-ee base. The builder pod has NO
# internet egress, which is why the compile cannot be moved into the Containerfile.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="${REGISTRY:-franken-registry.example.com:5000}"
# `franken-registry.example.com:5000` is a containerd MIRROR alias (see
# /etc/rancher/k3s/registries.yaml); the name itself does not resolve to a live
# host. buildah does not read that config, so it pulls and pushes against the real
# NodePort endpoint while the image keeps the mirror name the cluster pulls by.
ENDPOINT="${ENDPOINT:-192.168.1.240:30500}"
SUFFIX="${SUFFIX:?set SUFFIX=<tag suffix>, e.g. SUFFIX=f30}"
IMAGE="${REGISTRY}/automation-platform/receptor-ee:24.6.1-${SUFFIX}"
PUSH_IMAGE="${ENDPOINT}/automation-platform/receptor-ee:24.6.1-${SUFFIX}"
RECEPTOR_REF="${RECEPTOR_REF:-v1.4.8}"
NS="${NS:-image-build}"
POD="${POD:-receptor-bld}"
WORK="${WORK:-$(mktemp -d)}"

echo "[receptor] compiling $RECEPTOR_REF in $WORK"
git clone --depth 1 --branch "$RECEPTOR_REF" https://github.com/ansible/receptor.git "$WORK/src"
for p in "$REPO_ROOT"/receptor/patches/*.patch; do
  echo "[receptor] applying $(basename "$p")"
  git -C "$WORK/src" apply -v "$p"
done
( cd "$WORK/src" && CGO_ENABLED=0 go build -o "$WORK/stage/receptor" \
    -ldflags "-X 'github.com/ansible/receptor/internal/version.Version=${RECEPTOR_REF#v}+automation-platform'" \
    ./cmd/receptor-cl )
cp "$REPO_ROOT/receptor/Containerfile" "$WORK/stage/Containerfile"

kubectl -n "$NS" delete pod "$POD" --ignore-not-found --wait=true >/dev/null
kubectl -n "$NS" run "$POD" --image=quay.io/buildah/stable:v1.39 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"'"$POD"'","image":"quay.io/buildah/stable:v1.39","command":["sleep","3600"],"securityContext":{"privileged":true}}]}}' >/dev/null
# A pod that never becomes Ready is a failure to report, not something to wait out.
kubectl -n "$NS" wait --for=condition=Ready "pod/$POD" --timeout=300s

kubectl -n "$NS" exec "$POD" -- mkdir -p /build
tar -C "$WORK/stage" -cf - . | kubectl -n "$NS" exec -i "$POD" -- tar -C /build -xf -
kubectl -n "$NS" exec "$POD" -- buildah bud --isolation chroot --tls-verify=false \
  --build-arg "BASE=${ENDPOINT}/ansible/awx-ee:24.6.1" -t "$IMAGE" /build
kubectl -n "$NS" exec "$POD" -- buildah push --tls-verify=false "$IMAGE" "docker://$PUSH_IMAGE"
kubectl -n "$NS" delete pod "$POD" --wait=false >/dev/null

echo "built and pushed: $IMAGE"
echo "roll with: kubectl -n automation-platform set image deploy/awx-controller-task receptor=$IMAGE"
