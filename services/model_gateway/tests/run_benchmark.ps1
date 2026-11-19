param([Parameter(Mandatory)][string]$Manifest, [int]$Port=8789)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$local=Join-Path $repo '.model-local'
$voice=Join-Path $repo '.worktrees/d-voice-desktop/.voice-local'
$secret=ConvertTo-SecureString ((Get-Content (Join-Path $voice 'dashscope-key.dpapi') -Raw).Trim())
try { $env:DASHSCOPE_API_KEY=[Net.NetworkCredential]::new('', $secret).Password }
finally { $secret.Dispose() }
$config=Get-Content (Join-Path $voice 'dashscope-config.json') -Raw | ConvertFrom-Json
if ($config.region -ne 'cn-beijing') { throw 'Expected Beijing voice configuration.' }
$env:DASHSCOPE_WORKSPACE_ID=$config.workspace_id
$voices=Get-Content (Join-Path $voice 'comparison-voices.json') -Raw | ConvertFrom-Json
$env:COSYVOICE_VOICE_ID=$voices.voices.'cosyvoice-v3.5-flash'
$env:GATEWAY_TOKEN=(Get-Content (Join-Path $local 'gateway-token.txt') -Raw).Trim()
$env:GATEWAY_MODE='live'
$env:GATEWAY_DATA_DIR=Join-Path $local ('benchmark-'+(Get-Date -Format yyyyMMdd-HHmmss))
$env:BENCHMARK_MANIFEST=[IO.Path]::GetFullPath($Manifest)
$env:DEEPSEEK_API_KEY=''
@{MODEL_GATEWAY_URL="http://127.0.0.1:$Port";MODEL_GATEWAY_TOKEN=$env:GATEWAY_TOKEN} |
    ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $local 'mobile-benchmark.json')
Push-Location (Join-Path $PSScriptRoot '..')
try { & 'D:\dev\model-gateway-venv\Scripts\python.exe' -m uvicorn tests.benchmark_server:create_app --factory --host 127.0.0.1 --port $Port --no-access-log }
finally { Pop-Location }
