param([switch]$Status, [string]$WorkspaceId = '')
$ErrorActionPreference = 'Stop'
$voiceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$voiceLocal = Join-Path $voiceRoot '.voice-local'
$voiceKeyPath = Join-Path $voiceLocal 'dashscope-key.dpapi'
$voiceConfigPath = Join-Path $voiceLocal 'dashscope-config.json'
if ($Status) {
    [pscustomobject]@{
        EncryptedKeyPresent = Test-Path -LiteralPath $voiceKeyPath
        WorkspaceConfigPresent = Test-Path -LiteralPath $voiceConfigPath
    }
    return
}
Write-Host 'Use Alibaba Cloud Model Studio, China (Beijing). Do not paste the key into chat.'
$voiceWorkspace = $WorkspaceId.Trim()
if ($voiceWorkspace -and $voiceWorkspace -notmatch '^[a-zA-Z0-9][a-zA-Z0-9-]{0,127}$') {
    throw 'Invalid workspace ID. Enter the ID only, not a URL.'
}
if (-not $voiceWorkspace) { Write-Host 'Using the default Beijing endpoint. Workspace ID is optional.' }
$voiceSecret = Read-Host 'DashScope API Key (hidden)' -AsSecureString
if ($voiceSecret.Length -lt 10) { throw 'API Key is empty or too short.' }
New-Item -ItemType Directory -Force -Path $voiceLocal | Out-Null
try {
    # Windows DPAPI binds this encrypted value to this Windows account and machine.
    $voiceSecret | ConvertFrom-SecureString | Set-Content -LiteralPath $voiceKeyPath -Encoding ASCII
    @{ workspace_id = $voiceWorkspace; region = 'cn-beijing' } |
        ConvertTo-Json | Set-Content -LiteralPath $voiceConfigPath -Encoding UTF8
} finally { $voiceSecret.Dispose() }
Write-Host 'Saved locally with Windows DPAPI. No API request or billable synthesis was made.'
