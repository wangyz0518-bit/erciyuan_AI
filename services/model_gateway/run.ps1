param(
    [ValidateSet('live','mock')][string]$Mode='live',
    [int]$Port=8787,
    [string]$Python='D:\dev\model-gateway-venv\Scripts\python.exe',
    [string]$VoiceConfigRoot='',
    [switch]$UseExistingProxy
)
$ErrorActionPreference='Stop'
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$localRoot=Join-Path $repoRoot '.model-local'
New-Item -ItemType Directory -Force -Path $localRoot | Out-Null
if (-not $VoiceConfigRoot) { $VoiceConfigRoot=Join-Path $repoRoot '.worktrees/d-voice-desktop/.voice-local' }
function Read-LocalKey([string]$path) {
    $secret=ConvertTo-SecureString ((Get-Content -LiteralPath $path -Raw).Trim())
    try { return [Net.NetworkCredential]::new('', $secret).Password }
    finally { $secret.Dispose() }
}
if ($Mode -eq 'live') {
    $deepseekPath=Join-Path $localRoot 'deepseek-key.dpapi'
    if(Test-Path -LiteralPath $deepseekPath) { $env:DEEPSEEK_API_KEY=Read-LocalKey $deepseekPath }
    $dashPath=Join-Path $VoiceConfigRoot 'dashscope-key.dpapi'
    if(Test-Path -LiteralPath $dashPath) { $env:DASHSCOPE_API_KEY=Read-LocalKey $dashPath }
    $configPath=Join-Path $VoiceConfigRoot 'dashscope-config.json'
    if(Test-Path -LiteralPath $configPath) {
        $config=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        if($config.region -ne 'cn-beijing') { throw 'Expected Beijing voice configuration.' }
        $env:DASHSCOPE_WORKSPACE_ID=$config.workspace_id
    }
    $voicePath=Join-Path $VoiceConfigRoot 'comparison-voices.json'
    if(Test-Path -LiteralPath $voicePath) {
        $voices=Get-Content -LiteralPath $voicePath -Raw | ConvertFrom-Json
        $env:COSYVOICE_VOICE_ID=$voices.voices.'cosyvoice-v3.5-flash'
    }
}
$tokenPath=Join-Path $localRoot 'gateway-token.txt'
if(-not (Test-Path -LiteralPath $tokenPath)) {
    $bytes=New-Object byte[] 32
    $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
    try {$rng.GetBytes($bytes)} finally {$rng.Dispose()}
    [Convert]::ToBase64String($bytes) | Set-Content -Encoding ascii $tokenPath
}
$env:GATEWAY_TOKEN=(Get-Content -Raw -LiteralPath $tokenPath).Trim()
$env:GATEWAY_MODE=$Mode
$env:GATEWAY_DATA_DIR=Join-Path $localRoot "gateway-$Mode"
# This token gates a local development service. It is NOT a model provider key.
@{MODEL_GATEWAY_URL="http://127.0.0.1:$Port";MODEL_GATEWAY_TOKEN=$env:GATEWAY_TOKEN} |
    ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $localRoot "mobile-$Mode.json")
# Process-local route only, preserving the workstation's system proxy.
$bypass=@($env:NO_PROXY -split ',' | Where-Object {$_})
if ($UseExistingProxy) {
    if (-not $env:HTTPS_PROXY) { throw 'UseExistingProxy requires an existing HTTPS_PROXY environment variable.' }
    $env:GATEWAY_VOICE_PROXY=$env:HTTPS_PROXY
    $bypass=@($bypass | Where-Object {$_.Trim() -notmatch '(^|\.)deepseek\.com$' -and $_.Trim() -ne '*'})
} else {
    $bypass += 'api.deepseek.com'
    Remove-Item Env:GATEWAY_VOICE_PROXY -ErrorAction SilentlyContinue
}
$env:NO_PROXY=(@($bypass)+@('127.0.0.1','localhost')) -join ','
Push-Location $PSScriptRoot
try { & $Python -m uvicorn gateway.app:create_app --factory --host 127.0.0.1 --port $Port --no-access-log }
finally { Pop-Location }
