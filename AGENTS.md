# Repository Instructions

- Product baseline is **AAP 2.7**. Parity claims require live proof from a
  deployed controller — never render-only checks, mocks, stubs, canned
  responses, or verify-on-existence.
- The product name is **Automation Platform controller**. Never use "AWX" as a
  product name, brand, or label in user-facing prose or the console. Upstream
  source repositories (`ansible/awx`, `awx-plugins`, `dispatcherd`,
  `django-ansible-base`) and internal identifiers (`awx-controller`,
  `awx-gateway`, the `awx:` provider) are implementation details and may be
  named in engineering docs.
- `ansible-ui` is banned. The console is `pcf-console` only.
- Pin upstream SHAs in `sources.lock`; never build from a floating branch.
- Builds run on the prod1 `image-build` pipeline against the franken registry
  mirror only — no other egress. Never install build toolchains on localhost
  or alma1, and never run CI there.
- Do not commit secrets, kubeconfigs, tokens, or generated credentials.
- Requirement changes go through `docs/REQUIREMENTS.md` with a stable CTL-id;
  evidence changes go through `docs/parity-drivers.md`.
