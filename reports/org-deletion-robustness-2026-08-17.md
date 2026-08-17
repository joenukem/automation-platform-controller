# Org-deletion subsystem — fault-path review (2026-08-17)

After the parity sweep showed no controller *feature* gaps, this is a
robustness pass on the highest-risk *new* code we own: the ADR-0001
organization-deletion state machine, reaper, and pump. Each fault path was
reasoned through and, where testable, proven live on the candidate.

## Findings

| # | fault | before | after |
|---|---|---|---|
| R1 | explicit DELETE fails once (job won't cancel → RuntimeError → failed) | **stranded forever** — the pump retried pending/stuck but never failed, and no caller re-issues an explicit DELETE | **patch 0006**: pump retries failed on the 10-min backoff; proven live (a failed deletion stuck 15min → complete in 20s) |
| R2 | reaper double-dispatched on one deletion (pump race) | assumed idempotent | **confirmed live**: two reapers back-to-back → `complete`, org gone, progress not double-counted, no error |
| R3 | reaper crashes mid-reap | assumed resumable | resumable by construction: state stays `reaping`, its own org FK is nulled by cascade if the org was already deleted, the pump re-dispatches after 10min and the child re-scan is idempotent |
| R4 | a child fails to delete mid-plan | — | raises → `failed` → (R1) retried; re-scan skips already-deleted children, so transient failures converge; a permanently-undeletable child retries visibly (state=failed + error) rather than silently stranding |
| R5 | NOT NULL (patch 0005) + a child surviving the plan | — | `org.delete()` raises IntegrityError → `failed` → retried; the only way a covered type survives is the create-during-reap race, which the next reap clears |
| R6 | lease-expiry deletion fails | already self-healed | the lease GC's exclude() covers only non-terminal states, so an expired org with a `failed` deletion is re-picked-up and gets a fresh record; R1 now also covers it directly |

## Design note carried forward

A *permanently* failing deletion (R4 with a genuinely undeletable child)
retries every 10 minutes forever, staying visible via `state=failed` + error.
This matches the existing stuck-reap behavior (also uncapped) and the ADR's
"resumable, never abort" philosophy. If an operator-facing bound is ever
wanted, add an attempt counter to `OrganizationDeletion` and surface it — but
uncapped-but-visible is strictly safer than silent stranding, which is what
this subsystem exists to eliminate.

## Net

The org-deletion subsystem is now fault-tested, not just happy-path proven.
Its single real gap (R1) is closed and live-verified; R2–R6 are confirmed
sound. This is the kind of hardening the design agenda's D-8 calls for on the
controller's own code.
