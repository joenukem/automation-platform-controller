# Patch queue — our divergence from upstream

Applied in `series` order by `build/build.sh` (`git apply --index`) on top of
the `sources.lock` SHAs. Every patch is a deliberate, reviewed divergence:

- One logical change per patch, named `NNNN-short-slug.patch`.
- The patch header states the ADR or CTL requirement it implements and how it
  is tested (the build refuses nothing — review does).
- Rebasing onto new upstream SHAs = update `sources.lock`, re-apply the
  queue, fix conflicts, and re-run `build/test.sh` against the recorded
  baseline (CTL-072 stewardship).

Patch `0013` is the one queue entry that is not a code fix: it *enables* an
upstream subsystem (`ansible_base.authentication`) that was vendored but absent
from `INSTALLED_APPS`. See `docs/design/ADR-0003-platform-authenticators.md`.

Patch `0015` prevents cleanup load from consuming the dispatch worker pool: an
organization deletion persists its cancellation state and yields immediately,
then the database-backed pump retries it instead of sleeping in a worker.

The queue starting EMPTY is the Phase-1 result: zero code divergence was
needed to reach compatibility. The first series lands ADR-0001 increment 1
(the organization deletion state machine).
