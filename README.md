# Claude.Agent.Network

Records an agent container's HTTP(S) traffic with a mitmproxy sidecar, and turns the recording into JSON
the host can assert on.

Two parts:

- **`compose/sidecar.yaml`**: a Compose fragment with service `mitm` (`mitmproxy/mitmproxy:12.2.3`) in
  regular proxy mode on port 8080, and two networks: `inside` (`internal: true`, no route out) and `outside`.
  `mitm` sits on both, so it is the only way off `inside`. It generates its CA into the `mitm-ca` volume and
  streams flows to `capture/flows.mitm`. Egress is an allowlist: only hosts in `ALLOWED_HOSTS` (default
  `api.anthropic.com`, exact match) are forwarded; everything else gets a 403 and is recorded as refused.
- **`src/Claude.Agent.Network`**: a PowerShell module the *host* uses to read that capture.

## Using the sidecar

```yaml
include:
  - ../Claude.Agent.Network/compose/sidecar.yaml

services:
  agent:
    depends_on: { mitm: { condition: service_healthy } }
    networks: [inside]        # inside only: the internal network is the control
    environment:              # a convenience so tools find the proxy; not the control
      HTTPS_PROXY: http://mitm:8080
      HTTP_PROXY: http://mitm:8080
    volumes:
      - mitm-ca:/ca:ro        # trust /ca/mitmproxy-ca-cert.pem; never mount `capture`
```

The agent must trust `/ca/mitmproxy-ca-cert.pem` (system store, plus `NODE_EXTRA_CA_CERTS` for Node).
Put nothing else on `inside`: anything there with a second network would be another way out.
Do not redeclare `mitm-ca`, `capture`, `inside` or `outside` in the including file; Compose rejects the conflict.

## Egress allowlist

`src/addons/allowlist.py` is loaded into `mitm`. `ALLOWED_HOSTS` in `sidecar.yaml` is a comma-separated list of
exact host names (case-insensitive, no wildcards). Any other host is refused with `403` and the body
`{"refused": true, "host": "<host>"}`: HTTPS at `CONNECT`, before any upstream connection or TLS handshake;
plain HTTP, and requests whose Host header differs from the tunnel's, at the request. Refused flows stay in
`flows.mitm` with `refused` set. To allow another host, change `ALLOWED_HOSTS` in `sidecar.yaml` (design 4),
not the addon.

## Functions

| Function | What it does |
| --- | --- |
| `ConvertTo-NetworkCapture -FlowsPath <path> -OutPath <file> [-Volume <name>]` | Runs `mitmdump -nr <flows> -s capture_export.py` in a throwaway container from the sidecar's image. With `-Volume`, `-FlowsPath` is relative to that Docker volume (mounted read-only); otherwise it is a host file. Needs Docker. |
| `Get-NetworkCapture -Path <file> [-Summary]` | Parses the JSON, one object per flow; with `-Summary`, the `{allowed, refused, refusedHosts}` summary instead. |

`ConvertTo-NetworkCapture` writes `{summary: {allowed, refused, refusedHosts[]}, flows: [...]}`. Each flow: `method`,
`host`, `path`, `status` (null if no response), `requestBytes`, `responseBytes`, `started` (UTC), `refused`.
`Get-NetworkCapture` also reads a bare array or JSON lines, and computes the summary when none is stored.

```powershell
Import-Module ./src/Claude.Agent.Network
ConvertTo-NetworkCapture -Volume claude-agent-dev_capture -FlowsPath flows.mitm -OutPath ./capture.json
Get-NetworkCapture -Path ./capture.json | Where-Object host -eq 'api.anthropic.com'
```

mitmdump buffers the stream file, so stop the `mitm` service before converting.

The addon is `capture_export.py`, not `export.py`: mitmproxy names a script addon after its file, and
`export` is already taken by a built-in addon.

## Development

```powershell
Invoke-Build          # Pester: fixtures, plus the allowlist addon under mitmdump (needs Docker)
```

`tests/Allowlist.Tests.ps1` runs `tests/allowlist_driver.py` in the sidecar's image with `--network none`: mitmdump
with the addon in front of a local target, then `ConvertTo-NetworkCapture` on the stream file it wrote.
`Claude.Agent`'s Smoke task covers the whole path against the real API.
See [docs/design.md](docs/design.md).
