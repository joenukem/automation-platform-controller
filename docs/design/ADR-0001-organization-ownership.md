# ADR-0001 — Organizations are aggregate roots; deletion is an observable state machine

Status: **ACCEPTED** 2026-08-16 · Drives CTL-040, CTL-041, CTL-042, CTL-043
Acceptance evidence: the Phase-0 orphan experiment reproduced the defect class
on the devel line itself (project stranded, job template stranded *degraded*
with its inventory link nulled, inventory wedged in `pending_deletion`
forever), so this is owned work, not inherited behavior. Implementation lands
as the first patch series (see `../../patches/README.md`), increment order:
(1) deletion state machine + reaper (CTL-041) — **SHIPPED** as
`patches/0001-org-deletion-state-machine.patch`, deployed to prod1 as
`0.0.2-g9436511855` and proven live: DELETE with a RUNNING job -> 202 ->
job cancelled and preserved as history -> org 404 -> zero strands in any
unscoped list (the exact scenario that stranded three object types in the
Phase-0 experiment). The task-side pump self-resumed a deletion stranded by
an earlier broken publish path, demonstrating I3 in production before it was
formally tested. (2) session leases + GC, (3) scoped-by-default lists and
the NOT NULL schema tightening with the adopt-orphans migration.

## Context (all verified live, 2026-08-16)

In the frozen engine (awx 24.6.1) the organization is *not* an owner:

- `Inventory.organization`, `Project.organization`, and
  `WorkflowJobTemplate.organization` are `null=True, on_delete=SET_NULL`;
  only `Credential` and `ExecutionEnvironment` cascade.
- The API's `InventorySerializer.organization` is `required=True` **and**
  `allow_null=True` — you must name an org to create the resource, yet the
  schema happily represents the org-less state deletion produces.
- `OrganizationDetail` refuses deletion while jobs run (409) but never
  cascades; upstream chose SET_NULL so deleting an org cannot destroy job
  history (jobs FK inventories/projects).
- Observed steady state on our shared controller: **118 org-less inventories**
  (69 named `lab-inventory`) and 6 org-less workflow templates against 2 live
  orgs. Org-less rows appear in every unscoped list, so name-based UI clicks
  and first-result API resolution handed labs dead sessions' objects.
- Our provider's teardown deletes children in the right order but returns on
  the first error (one 409 → everything after it leaks). An hourly sweeper
  reclaims orphans; between runs a fast session campaign re-accumulates them.

The platform's dominant usage is **ephemeral session orgs**: created by the
provisioner, lifespan minutes-to-hours, torn down at session end. The frozen
engine's model treats every org as a permanent enterprise fixture.

## Decision

Make the organization a true aggregate root with an explicit, observable
deletion lifecycle:

1. **No org-less resources, by construction.** Every org-scoped resource
   carries a `NOT NULL` organization FK enforced in the schema. The state that
   produced 118 orphans becomes unrepresentable.

2. **Deletion is a resource, not a transaction.**
   `DELETE /organizations/:id` returns `202` and creates an
   `OrganizationDeletion` with a state machine:
   `pending → cancelling-jobs → reaping → complete | failed`, reporting
   per-type progress and current blockers. The reaper is an idempotent,
   resumable reconciliation loop — a failure mid-way leaves a resumable
   record, never a half-deleted org. Re-issuing DELETE resumes. Default
   policy cancels running jobs with a bounded grace period;
   `?mode=abort-if-active` restores the old refuse-while-busy behavior for
   callers that want it.

3. **History survives through tombstones, not orphans.** Deleting an org
   tombstones it (`lifecycle=deleted`) instead of removing the row. Jobs and
   their events remain FK-intact under the tombstone, and job rows already
   snapshot display names (`summary_fields`) at creation. Every list endpoint
   excludes tombstoned subtrees by default; `?include_deleted=true` exposes
   them for audit. Long-term, archived jobs can move to an append-only store
   and tombstones become droppable — that is an optimization, not a
   prerequisite.

4. **Scoped resolution is canonical.** All platform components resolve
   resources with `?organization=<id>`; the API guarantees org-scoped list
   parameters on every type. Unscoped first-result resolution (the
   `{{ inventory }}` failure mode) becomes unnecessary and lintable.

5. **Session leases are first-class.** An org may carry `expires_at` and an
   owner label; a controller GC loop feeds expired orgs through the same
   deletion state machine. This deletes the entire external-sweeper class
   (`awx-org-sweeper` cron) and makes session cleanup a controller invariant
   instead of an ops afterthought.

6. **Provider contract collapses.** pool-manager teardown becomes: request
   deletion, await `complete`. The ordered multi-DELETE (and its
   abort-on-first-409 bug class) disappears. Creation keeps the CTL-042
   rule: confirmed by read-back, 4xx is loud failure.

## Alternatives considered

- **CASCADE everywhere** — simplest schema, but org deletion silently
  destroys job history; upstream rejected this for good reason, so do we.
- **Keep SET_NULL + sweeper** — the status quo; mitigations decay (the
  sweeper missed workflow templates for weeks) and every new resource type
  re-opens the leak. Rejected.
- **Synchronous transactional cascade in the DELETE request** — atomic but
  unbounded request duration, and job cancellation cannot be transactional.
  The 202-plus-state-machine is the honest shape of the operation.

## Invariants (each becomes a property test and a leak-scan assertion)

- I1: no row of any org-scoped type has a NULL organization.
- I2: no default list response contains a resource under a tombstoned org.
- I3: an `OrganizationDeletion` reaches a terminal state in bounded time
  once its blockers are cancelled; retrying is always safe.
- I4: after `complete`, a full-type sweep finds zero live children
  (CTL-040's 20-cycle leak-scan).
- I5: an expired lease is reaped without operator action.

## Migration note

Existing NULL-org rows at cutover are adopted into a synthetic
`recovered-orphans` tombstone (visible only with `include_deleted`), so the
new schema's NOT NULL holds from day one without destroying anything.
