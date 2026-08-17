# CTL-002 — egress-free release build: status and completion plan

> **CLOSED 2026-08-16.** The vendored egress-free build is proven end-to-end:
> `buildah bud --network none --pull=never` builds `awx-25.0.0.dev0` green from
> the vendor bundle alone, and the tripwire on that image matches the
> egress-built baseline (1233 passed). Full acceptance evidence and the
> mechanism write-up are in **reports/ctl-002-airgap-acceptance.md**. The
> historical plan below is retained for context.

## Done (provable)

- **Base container images mirrored.** `quay.io/centos/centos:stream9` and
  `quay.io/ansible/receptor:devel` copied into
  `franken-registry.example.com:5000/mirror/`. `build/render_dockerfile.py`
  and `build/build.sh` rewrite both base `FROM`s and the receptor image to
  `$MIRROR_BASE` when set — verified the rendered Dockerfile has **zero
  quay.io references**.

## Capture pass — DONE (proven)

`build/vendor/Dockerfile.capture` runs in the mirrored `centos:stream9` base
(so wheels carry the right platform tags — the pitfall of capturing in the
buildah/Fedora pod is avoided) and produces `/vendor/{wheels,rpms}`:
**119M wheels + 302M RPMs** (with EPEL enabled for `inotify-tools`), pushed as
`automation-platform/vendor-capture:full` — **125M wheels + 379M RPMs**
covering BOTH the builder and final stages, including rsyslog pulled from its
Fedora copr repo (the non-obvious egress point). This is the once-per-
`sources.lock` egress-allowed pass.

## Remaining: vendored install + deny-egress proof (spec)

The bundle is complete; what's left is a `VENDORED=1` render mode that
transforms the rendered Dockerfile so both stages install offline, then one
build under a deny-egress NetworkPolicy. The exact transforms (per the mapped
Dockerfile):

1. Prepend a bundle stage: `FROM …/vendor-capture:full AS vendor`, and in each
   build stage `COPY --from=vendor /vendor /vendor` + write
   `/etc/yum.repos.d/vendored.repo` → `baseurl=file:///vendor/rpms gpgcheck=0`.
2. Rewrite each `dnf -y update && dnf install -y … && dnf config-manager
   --set-enabled crb && dnf -y install …` → `dnf install -y --disablerepo='*'
   --enablerepo=vendored …` (drop the update; the base image is current, and a
   partial repo can't satisfy a full update).
3. Replace the `epel-next-release`/`inotify-tools`/copr-rsyslog lines with a
   plain vendored install (both are in the bundle).
4. `ENV PIP_NO_INDEX=1 PIP_FIND_LINKS=/vendor/wheels` before the pip/`make`
   steps — pip and `make requirements_awx` both honor it.
5. Build with the builder pod under a NetworkPolicy denying all egress except
   the franken registry; green build + green tripwire = CTL-002 acceptance.

Effort: one focused session of Dockerfile transform + iterative debug. The
feasibility is proven (capture works, platform tags correct, every egress
point mapped and vendored).

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
