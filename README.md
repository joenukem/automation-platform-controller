# Automation Platform Controller

The execution controller of the Open Automation Platform: the service that owns
organizations, projects, inventories, credentials, job templates, workflows, and
job execution, exposed at `/api/v2` behind `awx-gateway` and surfaced in the
`pcf-console`.

## Why this project exists

The platform currently runs the frozen upstream engine release `awx 24.6.1`
(July 2024). Upstream paused releases and split the codebase into
service-oriented components — the UI (`ansible-ui`, banned in this platform),
shared auth/RBAC (`django-ansible-base`), credential/inventory plugins
(`awx-plugins`), and the task dispatcher (`dispatcherd`) — while Red Hat ships
the continued line only as the AAP 2.7 `automation-controller` product, with no
public upstream release. That leaves this platform two years behind the product
baseline it claims parity with, and stuck with verified defects in the frozen
release (organization deletion strands inventories and workflow templates;
teardown aborts partway on 409).

This project assembles, hardens, and releases a controller from the live
post-split upstream line so the platform tracks the AAP 2.7 baseline instead of
a frozen snapshot.

## Product naming

The product is the **Automation Platform controller** ("the controller").
Student-facing and console prose never says "AWX". Internal engine identifiers
(`awx-controller` deployments, the `awx:` provider, `awx-gateway`) are
implementation details and keep their names until a separately tested migration.

## Documents

- `docs/REQUIREMENTS.md` — the requirements to reach AAP 2.7 product parity,
  with requirement IDs, priorities, and acceptance proof for each.
- `docs/parity-drivers.md` — the verified defects and gaps in the running
  `awx 24.6.1` deployment that motivate specific requirements, with the evidence
  for each.

## Baseline facts (verified 2026-08-16)

- Running engine: upstream `awx 24.6.1` (`awx-controller-*` pods on prod1),
  the last release ever made of that repository.
- Upstream `ansible/awx` `devel` remains actively developed (last commit
  2026-08-14) but unreleased; it is the true upstream of AAP 2.7's controller.
- Split-out components: `ansible/django-ansible-base`, `ansible/awx-plugins`,
  `ansible/awx_plugins.interfaces`, `ansible/dispatcherd`, `ansible/ansible-ui`.
- No public repository exists for Red Hat's productized controller; its source
  is distributed only through subscription artifacts.
