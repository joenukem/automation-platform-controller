# ADR-0001 increment 3 — design note: making NOT NULL safe to land

Status: DESIGN · 2026-08-17 · The prerequisite analysis the increments 1–2
work uncovered, written down before any schema tightening ships.

## What produces org-NULL rows today, post-patches

With patches 0001–0004 live, the only remaining *producer* of `organization
= NULL` rows is Django's `on_delete=SET_NULL` firing when an Organization
row is deleted while it still has children. Our reaper deletes children
*before* the org, so in the normal path nothing is left to null. The residual
windows:

1. **Race**: an object created in a session's org *after* the reaper's child
   sweep but *before* the org row delete. Tiny window, real.
2. **Plan gaps**: any org-scoped type the child plan misses (audited:
   schedules cascade with their UJT; credentials and EEs CASCADE with the
   org; the plan covers workflows, templates, projects, inventories,
   notifiers, teams, labels).
3. **Legacy rows**: anything org-NULL from before the patches.

## Why NOT NULL is now the right kind of loud

With the constraint in place, `SET_NULL` firing becomes an IntegrityError on
the org delete — the reaper's transaction fails **loudly**, the deletion
record goes `failed` with the error, and the next pump tick retries after
re-sweeping children. That converts the race from *silent stranding* into
*visible retry*, which is exactly this project's failure philosophy. No
special-case code needed: the state machine already handles it.

## The `schedule_deletion` interactions, pinned

- `Inventory.schedule_deletion` sets `pending_deletion`, **clears
  `jobtemplates`** (this is what degraded the stranded JT in the Phase-0
  experiment — the clear runs even when the delete then wedges), and
  publishes from the web tier (fixed by patch 0004's adoption).
- It does NOT null the org FK; the org link survives until the actual
  delete. So NOT NULL does not conflict with pending_deletion — a
  pending-deletion inventory keeps its org until the row is removed.
- The org reaper deletes inventories via ORM `.delete()` directly, bypassing
  `schedule_deletion` entirely — no interaction.

Conclusion: **no rework of the async inventory flow is required** for
NOT NULL; patch 0004 already fixed the part that was broken.

## Landing plan for increment 3 (two patches)

1. **Patch A — adopt-orphans migration + NOT NULL.**
   - Data migration: any existing `organization IS NULL` row in Inventory /
     Project / WorkflowJobTemplate is adopted into a `recovered-orphans`
     organization created with `expires_at = now + 30d` (so the lease GC
     eventually clears the graveyard) — nothing is destroyed, and the rows
     become visible in exactly one place instead of every list.
   - Schema migration: `ALTER ... SET NOT NULL` on the three FKs; the FK
     rule stays SET_NULL at the Django level (the constraint is what makes
     it loud).
2. **Patch B — scoped-by-default enforcement** is *consumer* work, not
   schema: the platform components already pass `?organization=` after the
   D-3 driver fix; the controller-side piece is a conformance check in
   `build/verify.sh` asserting the locked list endpoints accept and honor
   the `organization` filter. No behavior change for other callers.

## Acceptance (unchanged from the ADR)

I1 (no org-NULL rows) becomes enforceable by the database itself; the
20-cycle leak scan plus one deliberate race test (create an object during
reaping, observe loud retry, observe eventual clean completion).
