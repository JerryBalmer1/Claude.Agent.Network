function ConvertTo-NetworkCapture {
    <#
    .SYNOPSIS
    Converts a mitmproxy flows file into JSON (one object per flow) using the sidecar's own image.
    .DESCRIPTION
    Runs `mitmdump -nr <flows> -s capture_export.py` in a throwaway container. With -Volume, -FlowsPath is a
    path inside that Docker volume (mounted read-only); otherwise it is a file on the host.
    Writes {summary: {allowed, refused, refusedHosts[]}, flows: [...]}; each flow has a `refused` boolean.
    .EXAMPLE
    ConvertTo-NetworkCapture -Volume claude-agent-dev_capture -FlowsPath flows.mitm -OutPath ./artifacts/capture.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $FlowsPath,
        [Parameter(Mandatory)][string] $OutPath,
        [string] $Volume,
        [string] $Image = $script:MitmImage
    )

    $outFull = [System.IO.Path]::GetFullPath($OutPath)
    $outDir = Split-Path -Parent $outFull
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    $mounts = @(
        '--mount', "type=bind,source=$outDir,target=/out"
        '--mount', "type=bind,source=$(Split-Path -Parent $script:ExportScript),target=/scripts,readonly"
    )
    if ($Volume) {
        $mounts += '--mount', "type=volume,source=$Volume,target=/capture,readonly"
        $inFile = '/capture/' + $FlowsPath.TrimStart('/').Replace('\', '/')
    }
    else {
        $flowsFull = (Resolve-Path -LiteralPath $FlowsPath).ProviderPath
        $mounts += '--mount', "type=bind,source=$(Split-Path -Parent $flowsFull),target=/in,readonly"
        $inFile = '/in/' + (Split-Path -Leaf $flowsFull)
    }

    $dockerArgs = @('run', '--rm', '--entrypoint', 'mitmdump') + $mounts + @(
        $Image, '-q', '-n', '-r', $inFile, '-s', '/scripts/capture_export.py',
        '--set', "capture_export_path=/out/$(Split-Path -Leaf $outFull)"
    )
    Write-Verbose "docker $($dockerArgs -join ' ')"
    $output = & docker @dockerArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "mitmdump export failed (exit $LASTEXITCODE): $($output -join [Environment]::NewLine)"
    }
    if (-not (Test-Path -LiteralPath $outFull)) {
        throw "mitmdump finished but '$outFull' was not written: $($output -join [Environment]::NewLine)"
    }

    # capture_export.py writes the flows; wrap them with the summary so a reader gets both from one file.
    # The array text is spliced in verbatim: a ConvertFrom-Json round trip would rewrite `started` as a DateTime.
    $flowsText = (Get-Content -LiteralPath $outFull -Raw).Trim()
    $summary = Get-CaptureSummary -Flows @($flowsText | ConvertFrom-Json) | ConvertTo-Json -Compress
    "{`"summary`": $summary,`n`"flows`": $flowsText}`n" | Set-Content -LiteralPath $outFull -Encoding utf8NoBOM -NoNewline
    Get-Item -LiteralPath $outFull
}
