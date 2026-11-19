# Offline regression: never reads or overwrites the real saved API key.
$ErrorActionPreference = 'Stop'
$voiceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$voiceTestBase = [IO.Path]::GetFullPath((Join-Path $voiceRoot '.voice-local'))
$voiceTestRoot = Join-Path $voiceTestBase ('config-test-' + [guid]::NewGuid().ToString('N'))
$voiceTestScripts = Join-Path $voiceTestRoot 'experiments/voice_poc'
New-Item -ItemType Directory -Path $voiceTestScripts -Force | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'configure_cloud.ps1') -Destination $voiceTestScripts
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'invoke_comparison.ps1') -Destination $voiceTestScripts
    function Read-Host {
        param([string]$Prompt, [switch]$AsSecureString)
        if (-not $AsSecureString) { throw 'Key-only setup unexpectedly asked for another value.' }
        return ConvertTo-SecureString 'local-config-test-only' -AsPlainText -Force
    }
    & (Join-Path $voiceTestScripts 'configure_cloud.ps1')
    $voiceTestConfig = Get-Content -LiteralPath (Join-Path $voiceTestRoot '.voice-local/dashscope-config.json') -Raw | ConvertFrom-Json
    if ($voiceTestConfig.region -ne 'cn-beijing' -or $voiceTestConfig.workspace_id) { throw 'Unexpected default configuration.' }
    @'
import os
assert os.environ['DASHSCOPE_API_KEY'] == 'local-config-test-only'
assert not os.environ.get('DASHSCOPE_WORKSPACE_ID')
assert 'dashscope.aliyuncs.com' in os.environ.get('NO_PROXY', '')
print('DPAPI file -> child environment: passed; no network request made.')
'@ | Set-Content -LiteralPath (Join-Path $voiceTestScripts 'compare_voices.py') -Encoding UTF8
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $voiceTestScripts 'invoke_comparison.ps1') -Cloud -Python (Join-Path $voiceRoot '.voice-local/cpu-venv/Scripts/python.exe') devices
    if ($LASTEXITCODE -ne 0) { throw 'Windows PowerShell credential wrapper regression failed.' }
} finally {
    $voiceResolvedTest = [IO.Path]::GetFullPath($voiceTestRoot)
    if (-not $voiceResolvedTest.StartsWith($voiceTestBase + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $voiceResolvedTest) -notmatch '^config-test-[0-9a-f]{32}$') {
        throw 'Refusing to clean a path outside the isolated test directory.'
    }
    Remove-Item -LiteralPath $voiceResolvedTest -Recurse -Force
}
