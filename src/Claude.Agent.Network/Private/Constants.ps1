# Keep in step with the image tag in compose/sidecar.yaml: the flows file format is version-specific.
$script:MitmImage = 'mitmproxy/mitmproxy:12.2.3'
$script:ExportScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'capture_export.py'
