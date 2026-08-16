# Risk Assessment — will this plan deliver a quality controller at parity?

Status: ACCEPTED HONESTY DOCUMENT · 2026-08-16

The one-sentence answer: **scoped parity (what the platform exercises) is
likely, conditional on two named risks; full AAP 2.7 parity is a separate,
costed track (FULL-PARITY-PLAN.md) that is likely except for mesh, which
should be demand-triggered.** "Parity" is only ever claimed against the
PARITY-LEDGER, never as an unqualified word.

## What makes the scoped goal credible

- The quality machinery is the right shape: an executable conformance spec
  that already runs (the DO467 suite), invariants as property tests, a chaos
  test per FMEA row, and the rule that a design is not done until its failure
  test is named.
- The integration surface (gateway, console, provider, driver) is ours,
  REST-based, and captured as `api-surface.lock` — compatibility is a finite
  tested object, not "whatever the old engine did".
- The platform's real usage is narrow and well-understood: session orgs,
  RBAC basics, templates/surveys, workflows, EEs as pods.

## Risk 1 — building from a construction site (SEVERITY: HIGH)

The composed line (`awx devel` + DAB + dispatcherd + plugins) is unreleased,
mid-refactor, and unproven outside Red Hat; the product build contains glue
we cannot see, and a 24.6.1→devel migration path may not exist across the
release pause. **Mitigation: the Phase-0 fallback gate (CTL-071)** — a
pre-agreed decision point with criteria and alternatives, so failure of the
composition premise costs a spike, not the project.

## Risk 2 — permanent fork stewardship (SEVERITY: HIGH, CHRONIC)

With upstream releases paused, we become release manager of this line
indefinitely: CVE watch, rebases, regressions. This is a standing cost, not
a one-time build. **Mitigation: CTL-072 prices it explicitly** (monthly
rebase cadence, CVE watch, named ownership); if that price is unacceptable,
the fallback gate's fork-24.6.1 option is cheaper to steward but further
from AAP 2.7 behavior.

## Risk 3 — the hard cores: D-2 and D-4 (SEVERITY: MEDIUM-HIGH)

The job lifecycle state machine and the event pipeline are where AAP has
years of hardening we would re-earn. Mitigation: they are designed first,
invariant-tested, and load-tested (CTL-050/051/052) before parity breadth
starts; the FULL track explicitly assumes they are done.

## Risk 4 — oracle weakness (SEVERITY: MEDIUM)

We cannot run Red Hat AAP 2.7 as a behavioral reference (subscription), so
fidelity is judged against documentation, public collection/CLI test suites,
and our own suite. Mitigation: FULL-PARITY-PLAN's oracle-discipline rule —
every cluster names its oracle before build; ambiguous behavior is flagged
"interpreted" in the ledger, never silently guessed.

## Risk 5 — scope creep in the name of parity (SEVERITY: MEDIUM)

Parity-for-parity's-sake burns the budget on breadth nobody uses (the
frozen engine's mesh machinery is the cautionary tale). Mitigation: the
ledger's OUT rulings with justifications, and F5 (mesh) gated on product
demand rather than completeness reflex.

## Conditions that flip the verdict

The scoped-1.0 "likely" holds only while ALL of these are true:

1. Phase 0 passes its gate (or the fallback is exercised deliberately).
2. The conformance suite remains the release authority — no parity claim on
   code review or upstream diff review alone.
3. Stewardship (CTL-072) stays funded; an unowned fork decays into exactly
   the frozen-snapshot problem this project exists to solve.
4. The ledger stays normative: every new AAP 2.7 patch release gets a ledger
   delta review (release notes → rulings), so "parity" tracks a moving
   product honestly.
