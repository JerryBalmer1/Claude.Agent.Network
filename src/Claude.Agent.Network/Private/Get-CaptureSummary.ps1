# Counts allowed and refused flows. A flow without `refused` (captures from before the allowlist) counts as allowed.
function Get-CaptureSummary {
    param([object[]] $Flows = @())

    $refused = @($Flows | Where-Object { $_.PSObject.Properties['refused'] -and $_.refused })
    [ordered]@{
        allowed      = $Flows.Count - $refused.Count
        refused      = $refused.Count
        refusedHosts = @($refused | ForEach-Object host | Sort-Object -Unique)
    }
}
