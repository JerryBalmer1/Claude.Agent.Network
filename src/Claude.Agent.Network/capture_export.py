"""mitmproxy addon: export flows as a JSON array, one object per flow.

    mitmdump -nr flows.mitm -s capture_export.py --set capture_export_path=/out/capture.json

Fields: method, host, path, status, requestBytes, responseBytes, started (UTC ISO 8601), refused
(true when the allowlist addon refused the flow; see src/addons/allowlist.py).
"""
import datetime
import json

from mitmproxy import ctx, http


class CaptureExport:
    def __init__(self):
        self.rows = {}

    def load(self, loader):
        loader.add_option("capture_export_path", str, "/out/capture.json", "Where to write the JSON array.")

    def _record(self, flow: http.HTTPFlow):
        req = flow.request
        resp = flow.response
        self.rows[flow.id] = {
            "method": req.method,
            "host": req.pretty_host,
            "path": req.path,
            "status": resp.status_code if resp else None,
            "requestBytes": len(req.raw_content or b""),
            "responseBytes": len(resp.raw_content or b"") if resp else 0,
            "started": datetime.datetime.fromtimestamp(req.timestamp_start, datetime.timezone.utc)
            .isoformat(timespec="milliseconds")
            .replace("+00:00", "Z"),
            "refused": bool(flow.metadata.get("refused")),
        }

    def response(self, flow: http.HTTPFlow):
        self._record(flow)

    def error(self, flow: http.HTTPFlow):
        if flow.id not in self.rows:
            self._record(flow)

    def done(self):
        rows = sorted(self.rows.values(), key=lambda r: r["started"])
        with open(ctx.options.capture_export_path, "w", encoding="utf-8") as f:
            json.dump(rows, f, indent=2)
            f.write("\n")


addons = [CaptureExport()]
