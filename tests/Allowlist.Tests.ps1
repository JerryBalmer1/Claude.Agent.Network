# The allowlist addon, end to end: tests/allowlist_driver.py runs mitmdump with src/addons/allowlist.py in the
# sidecar's image (--network none) against a local target, then ConvertTo-NetworkCapture converts the stream file.
# Needs Docker.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/Claude.Agent.Network/Claude.Agent.Network.psd1') -Force
    $image = & (Get-Module Claude.Agent.Network) { $script:MitmImage }
    $repo = Split-Path -Parent $PSScriptRoot
    $out = Join-Path $TestDrive 'out'
    New-Item -ItemType Directory -Path $out | Out-Null

    $log = & docker run --rm --network none --entrypoint python3 `
        --mount "type=bind,source=$(Join-Path $repo 'src/addons'),target=/addons,readonly" `
        --mount "type=bind,source=$PSScriptRoot,target=/tests,readonly" `
        --mount "type=bind,source=$out,target=/out" `
        $image /tests/allowlist_driver.py 2>&1
    if ($LASTEXITCODE -ne 0) { throw "allowlist_driver.py failed (exit $LASTEXITCODE): $($log -join "`n")" }

    $client = Get-Content (Join-Path $out 'client.json') -Raw | ConvertFrom-Json
    $captureJson = Join-Path $out 'capture.json'
    ConvertTo-NetworkCapture -FlowsPath (Join-Path $out 'flows.mitm') -OutPath $captureJson | Out-Null
    $flows = @(Get-NetworkCapture -Path $captureJson)
    $summary = Get-NetworkCapture -Path $captureJson -Summary
}

Describe 'allowlist.py' {
    Context 'ALLOWED_HOSTS' {
        It 'defaults to api.anthropic.com when unset or blank' {
            @($client.defaultAllowed) | Should -Be @('api.anthropic.com')
            @($client.blankAllowed) | Should -Be @('api.anthropic.com')
        }
    }

    Context 'what the client sees' {
        It 'forwards a request to a listed host' {
            $client.allowedPlain.status | Should -Be 200
            $client.allowedPlain.body | Should -Be 'target ok'
        }

        It 'refuses a plain request to an unlisted host with 403 and a JSON body' {
            $client.deniedPlain.status | Should -Be 403
            $body = $client.deniedPlain.body | ConvertFrom-Json
            $body.refused | Should -BeTrue
            $body.host | Should -Be 'denied.example'
        }

        It 'refuses a CONNECT to an unlisted host, so no TLS handshake follows' {
            $client.deniedConnect.status | Should -Be 403
            ($client.deniedConnect.body | ConvertFrom-Json).host | Should -Be 'denied-tls.example'
        }

        It 'refuses a request to a listed address whose Host header names another host' {
            $client.spoofedHost.status | Should -Be 403
            ($client.spoofedHost.body | ConvertFrom-Json).host | Should -Be 'evil.example'
        }

        It 'does not refuse a CONNECT to a listed host (matched case-insensitively); it only fails upstream offline' {
            $client.allowedConnect.status | Should -Be 502
            $client.allowedConnect.body | Should -Not -Match 'refused'
        }
    }

    Context 'what the capture records' {
        It 'keeps refused flows in flows.mitm, marked refused, including the refused CONNECT' {
            $refused = @($flows | Where-Object refused)
            @($refused.host | Sort-Object) | Should -Be @('denied-tls.example', 'denied.example', 'evil.example')
            ($refused | Where-Object host -eq 'denied-tls.example').method | Should -Be 'CONNECT'
            @($refused.status | Sort-Object -Unique) | Should -Be @(403)
        }

        It 'records the allowed flow as not refused' {
            $allowed = @($flows | Where-Object { -not $_.refused })
            $allowed.host | Should -Be '127.0.0.1'
            $allowed.status | Should -Be 200
        }

        It 'ConvertTo-NetworkCapture writes the summary' {
            $summary.allowed | Should -Be 1
            $summary.refused | Should -Be 3
            @($summary.refusedHosts) | Should -Be @('denied-tls.example', 'denied.example', 'evil.example')
        }
    }
}
