param(
    [string]$Python='D:\dev\windows-voice-lab-venv\Scripts\pythonw.exe',
    [string]$Config='',
    [string]$Data=''
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not $Config) {$Config=Join-Path $repo '.model-local/mobile-live.json'}
if (-not (Test-Path -LiteralPath $Python)) {throw 'Install the Windows voice lab environment as described in README.md.'}
if (-not (Test-Path -LiteralPath $Config)) {throw 'Start services/model_gateway/run.ps1 first to create the local gateway configuration.'}
$local=Join-Path $repo '.model-local/windows-voice-lab'
New-Item -ItemType Directory -Force -Path $local | Out-Null
$arguments=@('"'+(Join-Path $PSScriptRoot 'app.py')+'"','--config','"'+[IO.Path]::GetFullPath($Config)+'"')
if ($Data) {$arguments+=@('--data',('"{0}"' -f [IO.Path]::GetFullPath($Data)))}
# Only a local gateway address/token is read by this client. Provider keys stay server-side.
$process=Start-Process -FilePath $Python -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru
Write-Output "Windows voice test window started (PID $($process.Id))."
