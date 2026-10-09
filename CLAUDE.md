# CLAUDE.md

mitmproxy capture sidecar (Compose fragment) plus a host-side PowerShell 7.4+ module to read the capture.
One of four sibling repos expected side by side (e.g. `C:\__Code\`):

- `Claude.Agent` builds the agent image, `include:`s `compose/sidecar.yaml` from here, and its Smoke task
  is the only end-to-end test of `ConvertTo-NetworkCapture`.
- `Claude.Agent.Ledger` is the ledger module.
- `Claude.Agent.Network` (this repo).
- `Claude.Agent.Policy` is the tool policy and its Claude Code hooks, baked into the agent image.

## Layout

- `compose/sidecar.yaml` service `mitm`, volumes `mitm-ca` and `capture`. Consumers must not redeclare those volumes.
- `src/addons/allowlist.py` egress allowlist loaded by `mitm` (bind-mounted by `sidecar.yaml`); hosts come from `ALLOWED_HOSTS` there.
- `src/Claude.Agent.Network/` module; `capture_export.py` is the mitmproxy addon it runs. `Private/Constants.ps1` holds the image tag.
- `tests/` Pester with `fixtures/`; `Allowlist.Tests.ps1` needs Docker (runs `allowlist_driver.py` in the mitm image). Run through `tests/Invoke-Tests.ps1`.

## Commands

- `Invoke-Build` runs Pester (default). Pester only via `pwsh -NoProfile -File tests/Invoke-Tests.ps1`.

## Rules

- The image tag in `compose/sidecar.yaml` and `Private/Constants.ps1` must match: the flows file format is version-specific.
- Widen egress only via `ALLOWED_HOSTS` in `sidecar.yaml`; the addon stays exact-match, no wildcards (design 4).
- The `capture` volume is for the host. Never document or add a way to mount it into the agent.
