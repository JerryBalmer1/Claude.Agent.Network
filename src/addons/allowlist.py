"""mitmproxy addon: egress allowlist. Hosts not listed are refused and still recorded.

    mitmdump -s allowlist.py --save-stream-file /capture/flows.mitm

ALLOWED_HOSTS (environment): comma-separated host names, exact match, case-insensitive, no wildcards.
Unset or blank means "api.anthropic.com".

A refused flow gets a 403 with {"refused": true, "host": "<host>"} and flow.metadata["refused"] = True.
HTTPS is refused at CONNECT, so no upstream connection is opened and no TLS handshake happens; mitmproxy's
save addon never sees such a flow, so it is written to the stream file here. Plain requests (and requests
whose Host differs from the tunnel's) are refused in `request` and saved by the save addon as usual.
"""
import json
import logging
import os

from mitmproxy import ctx, http

DEFAULT_ALLOWED_HOSTS = "api.anthropic.com"


def parse_allowed_hosts(value: str | None) -> frozenset[str]:
    hosts = frozenset(h.strip().rstrip(".").lower() for h in (value or "").split(",") if h.strip())
    return hosts or parse_allowed_hosts(DEFAULT_ALLOWED_HOSTS)


class Allowlist:
    def __init__(self):
        self.allowed = parse_allowed_hosts(os.environ.get("ALLOWED_HOSTS"))
        logging.info(f"allowlist: {', '.join(sorted(self.allowed))}")

    def _allows(self, host: str) -> bool:
        return host.rstrip(".").lower() in self.allowed

    def _refuse(self, flow: http.HTTPFlow, host: str):
        flow.metadata["refused"] = True
        flow.response = http.Response.make(
            403,
            json.dumps({"refused": True, "host": host}),
            {"Content-Type": "application/json"},
        )
        logging.warning(f"refused {flow.request.method} {host}")

    def http_connect(self, flow: http.HTTPFlow):
        if not self._allows(flow.request.host):
            self._refuse(flow, flow.request.host)

    def http_connect_error(self, flow: http.HTTPFlow):
        if flow.metadata.get("refused"):
            save = ctx.master.addons.get("save")
            if save:
                save.save_flow(flow)

    def request(self, flow: http.HTTPFlow):
        # Both must pass: the connection target and the Host header (a tunnel to an allowed host
        # must not carry requests addressed to another).
        for host in (flow.request.host, flow.request.pretty_host):
            if not self._allows(host):
                self._refuse(flow, host)
                return


addons = [Allowlist()]
