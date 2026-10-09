# Changelog

## Unreleased

- `compose/sidecar.yaml`: networks `inside` (`internal: true`) and `outside`; `mitm` joins both, making it the
  agent's only route out. The proxy env on the agent is now a convenience, not the control (design 1).
- Egress allowlist: `src/addons/allowlist.py`, loaded by `mitm`, forwards only hosts in `ALLOWED_HOSTS` (set in
  `sidecar.yaml`, default `api.anthropic.com`, exact match). Others get 403 `{"refused": true, "host": ...}`, HTTPS
  at `CONNECT`, and are recorded in `flows.mitm` with `refused` metadata (design 4).
- `capture_export.py` adds `refused` per flow. `ConvertTo-NetworkCapture` writes `{summary, flows}`, the summary
  being `{allowed, refused, refusedHosts[]}`; `Get-NetworkCapture -Summary` returns it (computed for older files).
- Pester: `Allowlist.Tests.ps1` runs the addon under mitmdump in the sidecar's image (needs Docker); summary tests on a fixture.

## 0.1.0 - 2026-10-08

- `compose/sidecar.yaml`: service `mitm` on `mitmproxy/mitmproxy:12.2.3`, regular proxy mode on 8080,
  CA in `mitm-ca`, stream file in `capture`, TCP healthcheck.
- `ConvertTo-NetworkCapture` runs `mitmdump -nr` with `capture_export.py` in a throwaway container, from a host file or straight off a volume.
- `Get-NetworkCapture` parses the JSON (array or JSON lines).
- Pester suite against a three-flow fixture.
