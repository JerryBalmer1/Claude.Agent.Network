# Fixture-only tests. ConvertTo-NetworkCapture needs Docker and a real flows file: Allowlist.Tests.ps1 runs it on one
# produced by mitmdump, and the Smoke task in Claude.Agent (../Claude.Agent/.build.ps1) runs it end to end.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/Claude.Agent.Network/Claude.Agent.Network.psd1') -Force
    $fixture = Join-Path $PSScriptRoot 'fixtures/flows.json'
    $refusedFixture = Join-Path $PSScriptRoot 'fixtures/refused.json'
}

Describe 'Get-NetworkCapture' {
    It 'returns three flows from the fixture' {
        @(Get-NetworkCapture -Path $fixture).Count | Should -Be 3
    }

    It 'returns the hosts in order' {
        (Get-NetworkCapture -Path $fixture).host |
            Should -Be @('api.anthropic.com', 'registry.npmjs.org', 'statsig.anthropic.com')
    }

    It 'keeps method, status and byte counts' {
        $first = @(Get-NetworkCapture -Path $fixture)[0]
        $first.method | Should -Be 'GET'
        $first.status | Should -Be 401
        $first.responseBytes | Should -Be 130
    }

    It 'reads JSON lines as well as an array' {
        $jsonl = Join-Path $TestDrive 'flows.jsonl'
        Get-Content $fixture -Raw | ConvertFrom-Json | ForEach-Object { $_ | ConvertTo-Json -Compress } | Set-Content $jsonl
        @(Get-NetworkCapture -Path $jsonl).Count | Should -Be 3
    }
}

Describe 'capture summary' {
    It 'counts refused flows and lists refused hosts once each, sorted' {
        $s = Get-NetworkCapture -Path $refusedFixture -Summary
        $s.allowed | Should -Be 2
        $s.refused | Should -Be 3
        @($s.refusedHosts) | Should -Be @('http-intake.logs.us5.datadoghq.com', 'statsig.anthropic.com')
    }

    It 'counts flows without a refused field as allowed' {
        $s = Get-NetworkCapture -Path $fixture -Summary
        $s.allowed | Should -Be 3
        $s.refused | Should -Be 0
        @($s.refusedHosts) | Should -HaveCount 0
    }

    It 'reads the {summary, flows} file ConvertTo-NetworkCapture writes, preferring the stored summary' {
        $wrapped = Join-Path $TestDrive 'capture.json'
        '{"summary": {"allowed": 2, "refused": 3, "refusedHosts": ["stored.example"]}, "flows": ' +
            (Get-Content $refusedFixture -Raw) + '}' | Set-Content $wrapped
        @(Get-NetworkCapture -Path $wrapped).Count | Should -Be 5
        @(Get-NetworkCapture -Path $wrapped | Where-Object refused).host | Should -Contain 'statsig.anthropic.com'
        @((Get-NetworkCapture -Path $wrapped -Summary).refusedHosts) | Should -Be @('stored.example')
    }
}

Describe 'ConvertTo-NetworkCapture' {
    It 'is exported (behaviour is covered by Allowlist.Tests.ps1 and Claude.Agent Smoke)' {
        Get-Command ConvertTo-NetworkCapture -Module Claude.Agent.Network | Should -Not -BeNullOrEmpty
    }
}
