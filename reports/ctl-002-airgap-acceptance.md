# CTL-002 — egress-free release build: ACCEPTANCE

**Status: DONE.** The controller image builds with **zero network** from the
captured vendor bundle alone, and the resulting image is functionally identical
to the egress-built one.

## Acceptance criteria (from docs/REQUIREMENTS.md §CTL-002 / the build plan)

> Build with the builder pod under a NetworkPolicy denying all egress except the
> franken registry; green build + green tripwire = CTL-002 acceptance.

Met with a **stronger** proof than a deny-egress NetworkPolicy: the build ran
under `buildah bud --network none --pull=never`, i.e. **every `RUN` step had no
network namespace at all** — not merely a filtered egress, but zero network.
A NetworkPolicy still lets a build reach anything the policy forgets to block;
`--network none` cannot reach anything by construction. All base images
(`vendor-capture:full`, `mirror/centos:stream9`, `mirror/ansible/receptor`) were
already in local storage, so `--pull=never` needed no registry pull either.

## Evidence

- **Build:** `192.168.1.240:30500/automation-platform/controller:airgap-v8`
  (`sha256:566eafa84199…`), built on `ctl-dev-bld` (image-build ns) with
  `--network none --pull=never`. Log: `awx-25.0.0.dev0` built; all five
  git-sourced packages installed offline from the bundle —
  `ansible-runner-2.4.1.dev64+g27bdfc3b4`,
  `awx-plugins-core-0.2.0a1.dev7+g7c6a7cf97` (with the
  `credentials-github-app` extra), `awx-plugins-interfaces-0.0.1a6.dev599+gb52a9f809`,
  `django-ansible-base-2026.8.14.0.dev54+gf90ed8aec`, `certifi-2038.12.31`.
- **Tripwire:** `build/test.sh airgap-v8` →
  **1233 passed / 13 failed / 1 xfailed / 116 errors** — identical to the
  egress-built baseline (STEWARDSHIP ledger: tripwire 1233). The airgap image is
  not a degraded build; it is the same build produced without egress.
  Report: `reports/pytest-unit-airgap-v8.txt`.

## How it works (the render + capture mechanism)

Two once-per-`sources.lock` egress-allowed passes produce a self-contained
bundle, after which every build is offline.

### 1. Capture (`build/vendor/Dockerfile.capture`, egress allowed)
Runs inside the **target** `centos:stream9` base (so wheels carry the correct
`cp312`/`manylinux` tags — capturing in the buildah/Fedora pod would tag them
wrong). Produces `/vendor/{wheels,rpms}`, pushed as
`automation-platform/vendor-capture:full`:
- `pip download` the full `requirements.txt` closure + `virtualenv/supervisor/
  dumb-init`.
- **PEP-517 build backends** (`setuptools-scm<=9.2.0`, `setuptools`, `wheel`,
  `Cython`, `hatchling`, `poetry-core`, …) so source packages can build offline
  under pip's build isolation.
- **`pip wheel -r requirements_git.txt`** — builds the git-sourced packages into
  **wheels** (not sdists). This is the crux: a wheel needs no build at install
  time, so its version and its declared **extras** come straight from METADATA.
  An sdist would be re-built by pip at install, setuptools-scm would recompute a
  version that no longer matches the pinned local segment, and the
  `pkg[extra]==<version>` pin would fail to resolve.
- `dnf download --resolve --alldeps` the RPM set both stages install (builder +
  runtime lists, `inotify-tools` from EPEL, `podman`, and `rsyslog` from its
  Fedora copr — the non-obvious egress point), then `createrepo_c`.

### 2. Render (`build/render_dockerfile.py`, `VENDORED=1`)
Transforms the rendered upstream Dockerfile so both stages install offline:
- `FROM …/vendor-capture:full AS vendor` + `COPY --from=vendor /vendor /vendor`
  and a `file:///vendor/rpms` `vendored.repo` in each stage.
- Rewrites every `dnf … update/config-manager/install` to
  `dnf install --disablerepo='*' --enablerepo=vendored …`; drops the EPEL/copr
  fetches (both vendored) and the `ssh-keyscan github.com` (offline clones
  nothing).
- Sets `PIP_OPTIONS="--no-index --find-links /vendor/wheels --pre"`, which
  triggers awx's **supported airgap branch** in `Makefile:requirements_awx`
  (`if [[ "$(PIP_OPTIONS)" == *"--no-index"* ]]`): it installs
  `requirements.txt + requirements_local.txt` with no `--no-binary` and no git
  clones.
- **Generates `requirements_local.txt`** from `requirements_git.txt`, pinning
  each git package to the **exact** version found in the bundle wheel list
  (`VENDOR_WHEEL_LIST`) — pip will not select a local-segment pre-release
  (`…+gb52a9f809`) for a bare requirement even with `--pre`, so the exact `==`
  pin is required — and adds it to the Dockerfile's requirements `ADD` list
  (upstream ships only `requirements.txt/_git/_tower`).
- Clears the build-time offline pip flags in the shipped image
  (`ENV PIP_NO_INDEX=0`) so runtime pip (custom-EE deps, admin installs) still
  reaches an index. (`ENV KEY=` with an empty value is silently dropped by
  buildah, hence the explicit `=0`.)

## Debug trail (the hard part, for the next rebase)

Each was a distinct offline-build failure mode, fixed in order:
1. `printf`-with-`\n` repo file mangled through the escaping layers → `echo`-list.
2. `setuptools-scm` build-dep missing → capture PEP-517 build backends.
3. `cffi==2.0.0` "from versions: none" → really the Makefile's non-airgap branch
   (`--no-binary`, git clones) firing; fixed by setting `PIP_OPTIONS` to contain
   `--no-index` so the airgap branch runs.
4. `requirements_local.txt: No such file` → add it to the Dockerfile `ADD` list.
5. git packages "Could not find a version … (from versions: <the only version>)"
   → pre-release + local-version + extras from an **sdist**; fixed by capturing
   them as **wheels** and pinning exact versions.
6. Tripwire `django-debug-toolbar` "from versions: none" → the shipped image had
   `PIP_NO_INDEX=1` baked in (a latent runtime footgun) + the tripwire reused a
   cached image tag; fixed by `PIP_NO_INDEX=0` and a fresh tag per build.

## Reproduce

```
# 1. capture (egress allowed, once per sources.lock):
buildah bud -f build/vendor/Dockerfile.capture \
  --build-arg MIRROR_BASE=192.168.1.240:30500/mirror \
  -t 192.168.1.240:30500/automation-platform/vendor-capture:full .

# 2. render offline + build with zero network:
MIRROR_BASE=192.168.1.240:30500/mirror VENDORED=1 \
  VENDOR_IMAGE=192.168.1.240:30500/automation-platform/vendor-capture:full \
  VENDOR_WHEEL_LIST="$(ls /vendor/wheels)" \
  python3 build/render_dockerfile.py work/build/awx
buildah bud --network none --pull=never -t …/controller:airgap .
```
