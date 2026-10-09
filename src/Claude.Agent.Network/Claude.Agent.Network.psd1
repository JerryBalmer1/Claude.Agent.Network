@{
    RootModule           = 'Claude.Agent.Network.psm1'
    ModuleVersion        = '0.1.1'
    GUID                 = 'b2d47a1e-3c95-4f60-8e21-7a0c5d9f4e83'
    Author               = 'JerryBalmer1'
    Description          = 'Reads the mitmproxy sidecar capture for Claude.Agent containers.'
    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @('ConvertTo-NetworkCapture', 'Get-NetworkCapture')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{ PSData = @{ Tags = @('mitmproxy', 'capture', 'network') } }
}
