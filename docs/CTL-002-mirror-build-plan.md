# CTL-002 — egress-free release build: status and completion plan

## Done (provable)

- **Base container images mirrored.** `quay.io/centos/centos:stream9` and
  `quay.io/ansible/receptor:devel` copied into
  `franken-registry.example.com:5000/mirror/`. `build/render_dockerfile.py`
  and `build/build.sh` rewrite both base `FROM`s and the receptor image to
  `$MIRROR_BASE` when set — verified the rendered Dockerfile has **zero
  quay.io references**.

## Remaining: pip index + dnf repos

The build still reaches PyPI (`pip install build`, `make requirements_awx`),
git (the `requirements_git.txt` https clones), and CentOS Stream 9 + CRB dnf
repos. The foreman pulp on the cluster exists but has **no content synced**,
so it can't serve these as-is.

### Recommended: vendored-build (proves egress-free without a running mirror)

Cheaper and more portable than standing up and syncing a full pulp:

1. **Capture pass** (egress allowed, once per `sources.lock`):
   - `pip download` the exact wheel closure from
     `requirements.txt` + `requirements_git.txt` into `vendor/wheels/`.
   - `dnf download --resolve --alldeps` the RPM set the Dockerfile installs
     (the builder-stage list + `podman`, `inotify-tools`, receptor deps) into
     `vendor/rpms/`, plus a local `createrepo_c`.
   - Store the two `vendor/` trees as a bundle image in the franken registry
     (keyed by the `sources.lock` hash, like the controller tag).
2. **Dockerfile variant** (`MIRROR_BASE` + `VENDORED=1`):
   - `COPY vendor/rpms` + a local `.repo` pointing at it; `dnf install
     --disablerepo='*' --enablerepo=vendored`.
   - `pip install --no-index --find-links=/vendor/wheels`.
3. **Proof:** run `build/build.sh` with the builder pod under a NetworkPolicy
   that **denies all egress** except the franken registry. A green build +
   green tripwire is CTL-002's acceptance.

### Alternative: pulp-backed

Sync CentOS Stream 9 BaseOS/AppStream/CRB + EPEL into the cluster pulp and a
`pulp_python` remote of PyPI, point the build's `.repo` + `pip.conf` at pulp.
Heavier (gigabytes, a one-time egress-allowed sync) but gives a live mirror
other builds share.

## Effort / dependency

Either path is a few hours and needs one egress-allowed capture/sync pass —
it is not a quick win, and it is the last thing standing between the current
dev-loop build and a certified egress-free release build. The base-image half
(the part most likely to silently break in a disconnected environment) is
already closed.
