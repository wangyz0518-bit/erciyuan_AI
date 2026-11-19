param(
    [Parameter(Mandatory=$true)][string]$VoiceConfigRoot,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$Python='D:\dev\windows-voice-lab-venv\Scripts\python.exe',
    [string[]]$Variants=@('base','slow','soft','lower','husky','rate085')
)
$ErrorActionPreference='Stop'
$previousKey=$env:DASHSCOPE_API_KEY
$secret=ConvertTo-SecureString ((Get-Content -LiteralPath (Join-Path $VoiceConfigRoot 'dashscope-key.dpapi') -Raw).Trim())
try {
    $env:DASHSCOPE_API_KEY=[Net.NetworkCredential]::new('', $secret).Password
    & $Python (Join-Path $PSScriptRoot 'run.py') --local $VoiceConfigRoot --out $OutputDirectory --variants @Variants
    if ($LASTEXITCODE -ne 0) {throw 'Independent voice experiment failed; inspect sanitized output.'}
} finally {
    $env:DASHSCOPE_API_KEY=$previousKey
    $secret.Dispose()
}
