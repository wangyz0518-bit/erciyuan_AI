param(
    [ValidateSet('live','mock')][string]$Mode='live',
    [int]$Port=8788,
    [ValidateSet('auto','direct','proxy')][string]$Route='auto',
    [string]$Python='',
    [string]$RuntimeRoot='',
    [switch]$NoBrowser
)
$ErrorActionPreference='Stop'
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if(-not $Python){$Python=Join-Path $repoRoot '.model-local/conversation-venv/Scripts/python.exe'}
if(-not (Test-Path -LiteralPath $Python)){throw 'Prepare the isolated conversation Python environment as described in the Windows conversation guide.'}
$gitCommon=(& git -C $repoRoot rev-parse --path-format=absolute --git-common-dir).Trim()
if($LASTEXITCODE -ne 0){throw 'Cannot locate project configuration.'}
$mainRoot=Split-Path -Parent $gitCommon
$keyRoot=Join-Path $mainRoot '.model-local'
$voiceRoot=Join-Path $mainRoot '.worktrees/d-voice-desktop/.voice-local'
if(-not $RuntimeRoot){$RuntimeRoot=Join-Path $repoRoot '.model-local'}
$runtimeRoot=[IO.Path]::GetFullPath($RuntimeRoot)
$useProxy=($Route -eq 'proxy') -or ($Route -eq 'auto' -and [bool]$env:HTTPS_PROXY)
if($Route -eq 'proxy' -and -not $env:HTTPS_PROXY){throw 'Proxy route requires HTTPS_PROXY in this process.'}
$expectedRoute=if($useProxy){'proxy'}else{'direct'}
& $Python (Join-Path $PSScriptRoot 'prepare_assets.py')
if($LASTEXITCODE -ne 0){throw 'Voice detection asset installation failed.'}
$ready=$false
try{
    $health=Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 2
    if($health.protocols -notcontains 3 -or $health.mode -ne $Mode -or ($Route -ne 'auto' -and $health.speech_route -ne $expectedRoute)){throw 'Port is occupied by another service or connection route.'}
    $expectedRoute=$health.speech_route
    $ready=$true
}catch{
    if(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue){throw 'Port is occupied; choose another port.'}
}
if(-not $ready){
    # Changing ports must not start another process over the same databases.
    $pidFile=Join-Path $runtimeRoot 'conversation-server.pid'
    if(Test-Path -LiteralPath $pidFile){
        $recordedProcessId=0
        if([int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(),[ref]$recordedProcessId)){
            $existingProcess=Get-CimInstance Win32_Process -Filter "ProcessId=$recordedProcessId" -ErrorAction SilentlyContinue
            $serverScript=Join-Path $repoRoot 'services/model_gateway/run.ps1'
            if($existingProcess -and $existingProcess.CommandLine -and $existingProcess.CommandLine.IndexOf($serverScript,[StringComparison]::OrdinalIgnoreCase) -ge 0){
                throw 'This runtime directory already has a running gateway. Use its port, or choose a separate -RuntimeRoot and port.'
            }
        }
    }
    if($Mode -eq 'live'){
        & $Python (Join-Path $PSScriptRoot 'import_voices.py') (Join-Path $keyRoot 'gateway-live/voice_profiles.sqlite') (Join-Path $runtimeRoot 'gateway-live')
        if($LASTEXITCODE -ne 0){throw 'Voice catalog import failed.'}
    }
    New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
    $script=Join-Path $repoRoot 'services/model_gateway/run.ps1'
    $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$script+'"'),'-Mode',$Mode,'-Port',$Port,
        '-Python',('"'+$Python+'"'),'-KeyRoot',('"'+$keyRoot+'"'),'-VoiceConfigRoot',('"'+$voiceRoot+'"'),
        '-LocalRoot',('"'+$runtimeRoot+'"'))
    if($useProxy){$arguments+='-UseExistingProxy'}
    $shellExecutable=(Get-Process -Id $PID).Path
    $process=Start-Process $shellExecutable -ArgumentList $arguments -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $runtimeRoot 'conversation-server.log') `
        -RedirectStandardError (Join-Path $runtimeRoot 'conversation-server-error.log')
    $process.Id | Set-Content (Join-Path $runtimeRoot 'conversation-server.pid')
    for($i=0;$i -lt 40;$i++){
        Start-Sleep -Milliseconds 250
        try{$health=Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 1;if($health.protocols -contains 3){$ready=$true;break}}catch{}
        if($process.HasExited){break}
    }
}
if(-not $ready){throw 'Gateway failed to start. Inspect the local conversation-server-error.log.'}
$config=Get-Content -LiteralPath (Join-Path $runtimeRoot "mobile-$Mode.json") -Raw | ConvertFrom-Json
if(-not $NoBrowser){
    $url="http://127.0.0.1:$Port/conversation-lab/#token="+[Uri]::EscapeDataString($config.MODEL_GATEWAY_TOKEN)
    Start-Process $url
}
Write-Output "Windows conversation lab is ready on port $Port ($Mode, $expectedRoute)."
