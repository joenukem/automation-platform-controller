# Stewardship log (CTL-072)

This is a maintained fork of upstream `ansible/awx` (`devel` line) plus
`django-ansible-base`, `dispatcherd`, and `awx-plugins`, pinned in
`sources.lock` and diverged only through the reviewed `patches/` queue.
Upstream releases are paused, so this project is the release manager of the
line — the standing obligations below are the price of that, and an unowned
fork is a 1.0 release blocker.

## Owner

- **Maintainer of record:** platform (the automation-platform-controller
  project owner). Every rebase, CVE triage, and release decision below is that
  owner's responsibility until reassigned here.

## Monthly upstream rebase review

Cadence: **first week of each month.**

1. `git ls-remote https://github.com/ansible/awx devel` (and the other three
   sources) — record the new tip SHAs.
2. Read the diff since the pinned SHA for security fixes, migration changes,
   and anything touching the areas our patches modify (org deletion, access
   querysets, the dispatcher, serializers).
3. Bump `sources.lock`, re-apply the `patches/` queue, resolve conflicts.
4. `build/build.sh && build/test.sh` — the pytest baseline in
   `reports/BASELINE.md` must not regress without a recorded reason.
5. `build/verify.sh` against a scratch deploy — four legs green.
6. Record the rebase in the ledger below.

A patch that upstream has adopted (our fix landed there) is **retired from the
queue** at rebase time, not carried forever.

## CVE watch

- Watch: `ansible/awx`, `ansible/django-ansible-base`, `ansible/dispatcherd`,
  `ansible/awx-plugins` security advisories; plus the base image
  (`centos:stream9`) and the Python/JS dependency trees pulled at build.
- On a relevant advisory: pull the fix as an out-of-cycle `sources.lock` bump
  or a patch, run the full gate, ship. Do not wait for the monthly window.
- Every release attaches an SBOM (syft, per CTL-004); diff it against the
  prior release's SBOM to catch newly-introduced vulnerable transitive deps.

## Drop-the-fork path (if upstream resumes releases)

If `ansible/awx` cuts a release ≥ our devel pin that contains the behavior we
need:

1. Test that release image through `build/verify.sh` + the DO467 conformance
   subset.
2. For each patch in `patches/series`, check whether upstream now provides the
   behavior; retire the ones it does.
3. If the queue empties (or reduces to config-only), switch `sources.lock` to
   the released tag and treat this repo as a thin overlay — or retire it
   entirely and consume upstream directly.
4. Record the decision as an ADR.

The goal is not to fork forever; it is to carry the line only while upstream
cannot, and to hand it back the moment it can.

## Ledger

| date | action | from → to | gate |
|---|---|---|---|
| 2026-08-16 | initial pin (Phase 0) | — → awx `3fea070`, DAB `f90ed8a`, plugins `7c6a7cf`, dispatcherd `2026.3.25` | Phase 0 PASSED |
| 2026-08-17 | patch queue 0001–0006 shipped on the pinned base | (no source bump) | tripwire 1233; live-proven |

_Next scheduled rebase review: 2026-09 (first week)._
