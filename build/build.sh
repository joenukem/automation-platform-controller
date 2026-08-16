#!/usr/bin/env bash
# Reproducible controller build: sources.lock SHAs + patches/ -> image.
#
#   build/build.sh            # build + push, tag derived from inputs
#   TAG=mytag build/build.sh  # explicit tag
#
# Pipeline: clone upstreams at the pinned SHAs -> apply patches/series with
# git apply -> pin requirements_git.txt to the locked SHAs -> render the
# headless Dockerfile -> tar context -> buildah on the prod1 image-build
# builder pod (dnsPolicy Default — cluster DNS wildcards external names into
# Traefik; see docs/phase0/REPORT.md) -> push to the franken registry.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/labpool-prod1-k3s.yaml}"
REG_PUSH="192.168.1.240:30500"
REG_PULL="franken-registry.example.com:5000"
IMG="automation-platform/controller"
WORK="${WORK:-$here/work/build}"
BUILDER_NS=image-build
BUILDER=ctl-dev-bld

lock() { awk -v n="$1" '$1==n {print $2}' "$here/sources.lock"; }
AWX_SHA=$(lock awx); DAB_SHA=$(lock django-ansible-base)
PLUGINS_SHA=$(lock awx-plugins); IFACES_SHA=$(lock awx_plugins.interfaces)
[ -n "$AWX_SHA" ] || { echo "sources.lock missing awx sha" >&2; exit 1; }

# Tag = version prefix + hash of everything that determines the output.
VERSION_PREFIX=$(awk '$1=="version-prefix" {print $2}' "$here/sources.lock")
VERSION_PREFIX="${VERSION_PREFIX:-0.0.2}"
INPUT_HASH=$(cat "$here/sources.lock" "$here/build/render_dockerfile.py" "$here/build/build.sh" \
                 $(ls "$here"/patches/*.patch 2>/dev/null) 2>/dev/null | sha256sum | cut -c1-10)
TAG="${TAG:-${VERSION_PREFIX}-g${INPUT_HASH}}"
echo "== building ${IMG}:${TAG} (awx ${AWX_SHA:0:10})"

clone_at() { # repo-url sha dest
  local url="$1" sha="$2" dest="$3"
  if [ -d "$dest/.git" ] && [ "$(git -C "$dest" rev-parse HEAD 2>/dev/null)" = "$sha" ] \
     && [ -z "$(git -C "$dest" status --porcelain 2>/dev/null)" ]; then
    echo "  cached: $dest @ ${sha:0:10}"; return
  fi
  rm -rf "$dest"; mkdir -p "$dest"
  git -C "$dest" init -q
  git -C "$dest" remote add origin "$url"
  git -C "$dest" fetch -q --depth 1 origin "$sha"
  git -C "$dest" checkout -q FETCH_HEAD
  echo "  cloned: $dest @ ${sha:0:10}"
}

mkdir -p "$WORK"
clone_at https://github.com/ansible/awx "$AWX_SHA" "$WORK/awx"

# Patch queue — our divergence from upstream, auditable and ordered.
if [ -f "$here/patches/series" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] && [ "${p:0:1}" != "#" ] || continue
    echo "  patch: $p"
    git -C "$WORK/awx" apply --index "$here/patches/$p"
  done < "$here/patches/series"
fi

# Pin the branch-tracking git requirements to the locked SHAs (CTL-001).
python3 - "$WORK/awx/requirements/requirements_git.txt" "$DAB_SHA" "$PLUGINS_SHA" "$IFACES_SHA" <<'PY'
import re, sys
path, dab, plugins, ifaces = sys.argv[1:5]
s = open(path).read()
s = re.sub(r'(django-ansible-base(?:\[[^\]]*\])? @ git\+https://github.com/ansible/django-ansible-base)@[\w.-]+', r'\1@' + dab, s)
s = re.sub(r'(awx-plugins-core(?:\[[^\]]*\])? @ git\+https://github.com/ansible/awx-plugins.git)@[\w.-]+', r'\1@' + plugins, s)
if ifaces and ifaces != '(tip':
    s = re.sub(r'(awx-plugins-interfaces @ git\+https://github.com/ansible/awx_plugins.interfaces.git)(@[\w.-]+)?', r'\1@' + ifaces, s)
open(path, 'w').write(s)
print('  requirements_git pinned')
PY

python3 "$here/build/render_dockerfile.py" "$WORK/awx"

# Builder pod (idempotent; dnsPolicy Default is what makes egress work).
if ! kubectl -n $BUILDER_NS get pod $BUILDER >/dev/null 2>&1; then
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: {name: $BUILDER, namespace: $BUILDER_NS}
spec:
  restartPolicy: Never
  dnsPolicy: Default
  containers:
  - name: b
    image: quay.io/buildah/stable:v1.39
    command: ["sh","-c","sleep 86400"]
    securityContext: {privileged: true}
    volumeMounts:
    - {name: work, mountPath: /work}
    - {name: containers, mountPath: /var/lib/containers}
  volumes:
  - {name: work, emptyDir: {sizeLimit: 30Gi}}
  - {name: containers, emptyDir: {sizeLimit: 40Gi}}
EOF
fi
kubectl -n $BUILDER_NS wait --for=condition=Ready pod/$BUILDER --timeout=300s >/dev/null

CTX="$WORK/ctx.tgz"
tar -C "$WORK/awx" -czf "$CTX" --exclude=.git .
kubectl -n $BUILDER_NS exec $BUILDER -- sh -c 'rm -rf /work/ctl && mkdir -p /work/ctl'
kubectl cp "$CTX" $BUILDER_NS/$BUILDER:/work/ctl/ctx.tgz
kubectl -n $BUILDER_NS exec $BUILDER -- sh -c "cd /work/ctl && tar xzf ctx.tgz && \
  buildah bud --format docker --tls-verify=false \
    --build-arg VERSION=25.0.0.dev0 --build-arg SETUPTOOLS_SCM_PRETEND_VERSION=25.0.0.dev0 \
    -t $REG_PUSH/$IMG:$TAG . 2>&1 | tail -3 && \
  buildah push --tls-verify=false $REG_PUSH/$IMG:$TAG 2>&1 | tail -1"
echo "== pushed ${REG_PULL}/${IMG}:${TAG}"
echo "$TAG" > "$here/work/last-build-tag"
