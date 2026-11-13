[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Cloud,
    [switch]$CudaOverlay,
    [string]$Python,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$ScriptArgs
)
$ErrorActionPreference = 'Stop'
$voiceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not $Python) { $Python = Join-Path $voiceRoot '.voice-local/cpu-venv/Scripts/python.exe' }
if (-not (Test-Path -LiteralPath $Python)) { throw 'Python not found. Supply -Python with your environment path.' }
$voiceOldKey = $env:DASHSCOPE_API_KEY
$voiceOldWorkspace = $env:DASHSCOPE_WORKSPACE_ID
$voiceOldPythonPath = $env:PYTHONPATH
$voiceOldOffline = $env:HF_HUB_OFFLINE
$voiceOldTransformersOffline = $env:TRANSFORMERS_OFFLINE
try {
    if ($Cloud) {
        $voiceKeyPath = Join-Path $voiceRoot '.voice-local/dashscope-key.dpapi'
        $voiceConfigPath = Join-Path $voiceRoot '.voice-local/dashscope-config.json'
        if ((Test-Path -LiteralPath $voiceKeyPath) -and (Test-Path -LiteralPath $voiceConfigPath)) {
            $voiceConfig = Get-Content -LiteralPath $voiceConfigPath -Raw | ConvertFrom-Json
            if ($voiceConfig.region -ne 'cn-beijing') { throw 'This experiment uses cn-beijing only.' }
            $voiceSecret = Get-Content -LiteralPath $voiceKeyPath -Raw | ConvertTo-SecureString
            try { $env:DASHSCOPE_API_KEY = [Net.NetworkCredential]::new('', $voiceSecret).Password }
            finally { $voiceSecret.Dispose() }
            $env:DASHSCOPE_WORKSPACE_ID = $voiceConfig.workspace_id
        }
        if (-not $env:DASHSCOPE_API_KEY -or -not $env:DASHSCOPE_WORKSPACE_ID) {
            throw 'Run configure_cloud.ps1 first, or configure both DashScope environment variables.'
        }
    }
    if ($CudaOverlay) {
        # Existing workstation: CUDA wheels are separate from Qwen's CPU dependency environment.
        $voiceGpuSite = Join-Path $voiceRoot '.voice-local/ref-venv/Lib/site-packages'
        $voiceQwenSite = Join-Path $voiceRoot '.voice-local/cpu-venv/Lib/site-packages'
        if (-not (Test-Path -LiteralPath (Join-Path $voiceGpuSite 'torch'))) { throw 'CUDA overlay not found.' }
        $env:PYTHONPATH = $voiceGpuSite + [IO.Path]::PathSeparator + $voiceQwenSite
        $env:HF_HUB_OFFLINE = '1'
        $env:TRANSFORMERS_OFFLINE = '1'
    }
    & $Python (Join-Path $PSScriptRoot 'compare_voices.py') @ScriptArgs
    $voiceExitCode = $LASTEXITCODE
} finally {
    $env:DASHSCOPE_API_KEY = $voiceOldKey
    $env:DASHSCOPE_WORKSPACE_ID = $voiceOldWorkspace
    $env:PYTHONPATH = $voiceOldPythonPath
    $env:HF_HUB_OFFLINE = $voiceOldOffline
    $env:TRANSFORMERS_OFFLINE = $voiceOldTransformersOffline
}
exit $voiceExitCode
