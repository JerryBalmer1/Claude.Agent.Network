function Get-NetworkCapture {
    <#
    .SYNOPSIS
    Reads the JSON written by ConvertTo-NetworkCapture and returns one object per flow, or with -Summary the
    {allowed, refused, refusedHosts} summary.
    .DESCRIPTION
    Accepts what ConvertTo-NetworkCapture writes ({summary, flows}), a bare JSON array (what capture_export.py
    writes) or JSON lines. Without a stored summary, -Summary computes it from the flows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [switch] $Summary
    )

    $text = (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop)
    $stored = $null
    $flows = @()
    if (-not [string]::IsNullOrWhiteSpace($text)) {
        if ($text.TrimStart().StartsWith('[')) {
            $flows = @($text | ConvertFrom-Json)
        }
        # Several JSON lines do not parse as one document; that falls through to the JSON lines case.
        elseif (($doc = try { $text | ConvertFrom-Json } catch { $null }) -and $doc.PSObject.Properties['flows']) {
            $flows = @($doc.flows)
            $stored = $doc.PSObject.Properties['summary']?.Value
        }
        else {
            $flows = @(foreach ($line in ($text -split "`r?`n")) {
                    if ($line.Trim()) { $line | ConvertFrom-Json }
                })
        }
    }

    if ($Summary) {
        if ($stored) { $stored } else { [pscustomobject](Get-CaptureSummary -Flows $flows) }
    }
    else {
        $flows
    }
}
