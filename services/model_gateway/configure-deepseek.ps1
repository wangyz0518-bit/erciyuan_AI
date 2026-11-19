$ErrorActionPreference = 'Stop'
$configRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../.model-local'))
New-Item -ItemType Directory -Force -Path $configRoot | Out-Null
Write-Host 'DeepSeek official endpoint: https://api.deepseek.com/chat/completions'
Write-Host 'Paste your DeepSeek API Key below. Input is hidden and stays on this Windows account.'
$secret = Read-Host 'DeepSeek API Key' -AsSecureString
try {
    if ($secret.Length -lt 10) { throw 'Key looks empty or too short; nothing saved.' }
    $secret | ConvertFrom-SecureString | Set-Content -Encoding utf8 (Join-Path $configRoot 'deepseek-key.dpapi')
    Write-Host 'Saved encrypted local configuration. No key is printed or committed to Git.'
} finally { $secret.Dispose() }
