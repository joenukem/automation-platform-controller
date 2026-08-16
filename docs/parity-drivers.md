# Parity Drivers — verified evidence motivating the requirements

Everything here was observed live on the platform (prod1 / franken), not
assumed. Cross-references: `lab-content/docs/AAP-PLATFORM-DEFECTS.md` and
`lab-content/docs/LAB-PLATFORM-REFERENCE.md`.

## D1 — the engine is a frozen snapshot two years behind the baseline

`awx.__version__` in the running controller-web pod is **24.6.1**
(released 2024-07-02, the final release of that repository). Upstream paused
releases for a service-oriented refactor and kept developing on `devel`
(active as of 2026-08-14); Red Hat ships the continued line only as the
AAP 2.7 product with no public release. → CTL-001, CTL-013.

## D2 — organization deletion strands resources (F18)

Verified in the running engine's model layer: `Inventory.organization`,
`Project.organization`, and `WorkflowJobTemplate.organization` are
`null=True, on_delete=SET_NULL`; `OrganizationDetail` refuses deletion while
jobs run (409) rather than cascading. Observed steady state: **118 orphaned
inventories** (69 named `lab-inventory`) and **6 orphaned workflow templates**
against 2 live organizations. The provider's teardown deletes in the right
order but returns early on the first 409, which is how remnants escape.
Mitigation in place: hourly `awx-org-sweeper` cron (extended 2026-08-16 to
reclaim workflow templates). → CTL-040, CTL-041.

## D3 — orphans poison unscoped resolution

lab-webapp's driver resolves `{{ inventory }}`/`{{ project }}` with an
unscoped `?page_size=1` query, and console steps click rows by visible name.
With D2's orphans present, labs received dead sessions' objects — failures
that masqueraded as flakiness. → CTL-043.

## D4 — concurrency fabricates failures (LAB-PLATFORM-REFERENCE §3c)

Identical content and console: 3 labs failed at CI MAX=8, all passed at MAX=3
in ~60s each; a later MAX=3 sweep degraded again as D2 orphans accumulated
mid-sweep. The engine's list/query behavior under concurrent session churn is
the platform's tightest bottleneck. → CTL-050, CTL-052.

## D5 — provisioning gaps force console-side workarounds (F15)

The `awx:` provider cannot stage surveys, `ask_*` prompts, `extra_vars`, or
inventory variables (no such fields in `AWXJobTemplateSpec`/
`AWXInventorySpec`). Labs now author surveys in the console, which is
pedagogically right, but the controller must keep exposing complete
survey/prompt APIs so either side can own it. → CTL-024, CTL-044.

## D6 — 4xx-as-success in provisioning (F17)

Hub provisioning accepts HTTP 400 as created, so sessions go Ready with
recorded resources that do not exist, failing much later in console steps.
The same pattern must be impossible in the controller provisioning path.
→ CTL-042.

## D7 — launch wizard history (F9, fixed)

A template with prompts/survey could be driven to the final wizard step with
no launch POST ever issued; fixed in pcf-console by launching from the
wizard's own footer. Kept as a driver because CTL-044's structured-error
contract is what prevents the class from recurring. → CTL-044.

## D8 — EE realism requires distinct images (F16, fixed)

Two provisioned EEs pointed at one image, making the taught failure
impossible; fixed by building `awx-ee-minimal` (community.general removed,
verified in-image). The controller must keep honoring per-template EE
selection so these distinctions stay real. → CTL-026.
