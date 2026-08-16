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

## Development loop

- `build/build.sh` — reproducible build: `sources.lock` SHAs + `patches/`
  queue -> headless image on the prod1 builder -> registry. Tag derives from
  the input hash.
- `build/test.sh` — upstream unit-test subset inside the built image; the
  recorded baseline is what every patch is judged against.
- `build/verify.sh` — conformance gate for a running controller: locked
  api-surface replay + pool-manager provider conformance. The DO467 serial
  suite is the third leg, run from lab-content.
- `patches/` — our divergence from upstream as an ordered, reviewed queue
  (currently empty; ADR-0001 increment 1 lands first).

## Documents

- `docs/REQUIREMENTS.md` — the requirements (CTL-xxx) with priorities and
  acceptance proof for each, including parity governance (CTL-070..072).
- `docs/design/PARITY-LEDGER.md` — NORMATIVE: every AAP 2.7 controller feature
  with an explicit ruling (IN-1.0 / FULL / GATEWAY / OUT).
- `docs/design/FULL-PARITY-PLAN.md` — the costed milestones (F1-F5) from
  scoped 1.0 to full parity; mesh is demand-triggered.
- `docs/design/RISK-ASSESSMENT.md` — whether this plan is likely to deliver,
  the two high-severity risks, and the conditions that flip the verdict.
- `docs/design/DESIGN-AGENDA.md` — what must be designed (D-1..D-12) and why
  upstream commit review is supply chain, not design.
- `docs/design/ADR-0001-organization-ownership.md` — organizations as
  aggregate roots; deletion as an observable state machine.
- `docs/parity-drivers.md` — the verified defects in the running `awx 24.6.1`
  deployment that motivate specific requirements, with evidence.

## Baseline facts (verified 2026-08-16)

- Running engine: upstream `awx 24.6.1` (`awx-controller-*` pods on prod1),
  the last release ever made of that repository.
- Upstream `ansible/awx` `devel` remains actively developed (last commit
  2026-08-14) but unreleased; it is the true upstream of AAP 2.7's controller.
- Split-out components: `ansible/django-ansible-base`, `ansible/awx-plugins`,
  `ansible/awx_plugins.interfaces`, `ansible/dispatcherd`, `ansible/ansible-ui`.
- No public repository exists for Red Hat's productized controller; its source
  is distributed only through subscription artifacts.

## Sole sanctioned engine source

As of 2026-08-16 the frozen engine (`ansible/awx:24.6.1`) is banned as a target
across the platform: lab-content (`tools/ban-frozen-controller.sh`), awx-gateway
(`scripts/ban-frozen-engine.sh` + `FROZEN-ENGINE-EXCEPTION.md`, the bounded
register for the currently-running stack), and every
`open-automation-platform-*` repo plus `awx-telemetry-agent` (AGENTS.md policy).
This project is the only sanctioned controller line; the runtime exception on
prod1/franken expires at the CTL-013 cutover.
