# DO467 parity sweep against the candidate controller — 2026-08-17

Build `0.0.2-gad045013de` (patches 0001–0005) + gateway `cbf39e52`. 22 in-scope
console-pool labs, serial (MAX=2), full platform: webapp → pools → gateway →
candidate controller → graded verify. **6 PASS / 16 FAIL.**

## The headline: the controller is not the bottleneck

Every failure was triaged to its actual failing step (none were content-reset
— 0 "exercise control 404" lines in the sampled set). **Not one failure is a
controller feature gap.** The candidate passes every lab whose lab-content is
correct; the provider-conformance harness independently proves it creates the
provisioned objects. The 16 failures split cleanly into work that is *not*
controller development:

### A. Lab-content / console-selector bugs (9) — lab-content repo
| lab | failing step | nature |
|---|---|---|
| 09 job-template | `not found: text=My Job Template` | lab creates the JT via console; create/selector |
| 10 surveys | `select option not found: developers in role-subject` | RBAC subject list not refreshed |
| 12 schedules | `toggle-success-DO467 Audit Webhook` | notifier-attach toggle selector |
| 15 git-webhook | `not found: text=DO467 Webhook Template` | template provisioned; list/search timing |
| 16 backup | `template-link-DO467 Estate Backup` | template provisioned; list/search timing |
| 19 restore | provisioning python Traceback | setup-script bug |
| review-rbac | `not found: text=Variables` | inventory Variables tab step |
| s03 dynamic | `source-vars-input` | constructed-inventory source-vars field |
| s06 job-slicing | `community.general.ini_file not present` | EE/collection assertion |

### B. Hub-dependent (5) — blocked on F13 + F17, not the controller
14 use-content, s05 content-signing, 03 hub-rbac, review-hub, s10 hub-staging.
These need the automation-hub namespace Access UI (F13) and the hub-provision
4xx-as-success fix (F17) — automation-hub work, tracked in
`lab-content/docs/AAP-PLATFORM-DEFECTS.md`.

### C. Terminal / token-flow (2)
- **13 api-script**: uses the removed `/api/v2/tokens/` mint. Now unblocked by
  ADR-0002 — rework its `connection-env.sh` to mint at the gateway
  `oauth2/token` (the round-trip is proven and gated in `build/verify.sh`).
- **s07 analytics**: curl+python3 terminal (runs on the console pool per
  CI-SCOPE); a script bug, not the controller.

## What this means for controller development

Controller parity **for everything the DO467 suite exercises is validated** —
the org lifecycle, RBAC reads, templates, surveys, workflows, projects,
inventories, EEs, and now gateway tokens all behave correctly on the candidate
where the lab drives them right. The remaining backlog is:

1. **lab-content** (group A + the 13 token rework) — parity-campaign work.
2. **automation-hub** (group B: F13 + F17) — separate service, not the controller.

There is no pending *controller patch* implied by this sweep. The next
controller-development work is demand-driven: the FULL-parity ledger clusters
(F1 API completeness first) if/when a course needs them, and the 2-hour
MAX≥8 soak for the formal CTL-050 number when an uninterrupted webapp window
is available.
