#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Device = 'emulator-5582',
    [string]$GatewayConfig = ''
)

$ErrorActionPreference = 'Stop'
$appRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = [IO.Path]::GetFullPath((Join-Path $appRoot '../..'))

if ([string]::IsNullOrWhiteSpace($GatewayConfig)) {
    $GatewayConfig = Join-Path $repoRoot '.model-local/mobile-v4-5582.json'
}
if (!(Test-Path -LiteralPath $GatewayConfig -PathType Leaf)) {
    throw "Create a local v3 gateway configuration at $GatewayConfig."
}
$configPath = (Resolve-Path -LiteralPath $GatewayConfig).Path
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -AsHashtable
$gateway = $null
if (![uri]::TryCreate([string]$config.MODEL_GATEWAY_URL, [UriKind]::Absolute, [ref]$gateway) -or
    $gateway.Scheme -ne 'http' -or $gateway.Host -notin @('127.0.0.1', 'localhost') -or
    $gateway.UserInfo -or $gateway.AbsolutePath -ne '/' -or $gateway.Query -or $gateway.Fragment -or
    $config.MODEL_GATEWAY_PROTOCOL -ne 'v3' -or
    [string]::IsNullOrWhiteSpace([string]$config.MODEL_GATEWAY_TOKEN)) {
    throw 'The launch configuration must contain a loopback HTTP v3 gateway and its local development token.'
}

if ((& adb -s $Device get-state) -ne 'device' -or $LASTEXITCODE -ne 0) {
    throw "ADB device $Device is unavailable."
}

# Read only response headers, so conversation history stays out of the launcher.
$handler = [Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$handler.UseProxy = $false
$client = [Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(5)
$client.DefaultRequestHeaders.Authorization =
    [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $config.MODEL_GATEWAY_TOKEN)
try {
    foreach ($role in 'xing', 'yue', 'sprout') {
        $endpoint = [uri]::new($gateway, "/v3/conversations/$role")
        try {
            $response = $client.GetAsync($endpoint, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        } catch {
            throw "Cannot reach the local v3 gateway on port $($gateway.Port)."
        }
        try {
            if (!$response.IsSuccessStatusCode) {
                throw "V3 gateway check for $role returned HTTP $([int]$response.StatusCode)."
            }
        } finally {
            $response.Dispose()
        }
    }
} finally {
    $client.Dispose()
}

$previousJavaHome = $env:JAVA_HOME
if (!$env:JAVA_HOME -and !(Get-Command java.exe -ErrorAction SilentlyContinue) -and $env:ANDROID_HOME) {
    $studioJdk = Join-Path (Split-Path -Parent $env:ANDROID_HOME) 'android-studio/jbr'
    if (Test-Path -LiteralPath (Join-Path $studioJdk 'bin/java.exe') -PathType Leaf) {
        $env:JAVA_HOME = $studioJdk
    }
}

try {
    $port = "tcp:$($gateway.Port)"
    & adb -s $Device reverse $port $port
    if ($LASTEXITCODE -ne 0) { throw "Failed to configure the ADB reverse for $Device." }

    $branch = & git -C $repoRoot branch --show-current
    Write-Host "Launching apps/mobile on $Device from $branch with gateway v3 on port $($gateway.Port)."
    Push-Location $appRoot
    try {
        & flutter run --debug --no-resident -d $Device -t lib/main.dart "--dart-define-from-file=$configPath"
        if ($LASTEXITCODE -ne 0) { throw "Flutter launch failed with exit code $LASTEXITCODE." }
    } finally {
        Pop-Location
    }
} finally {
    $env:JAVA_HOME = $previousJavaHome
}
