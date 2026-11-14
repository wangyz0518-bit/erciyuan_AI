param(
    [ValidateSet('analyze','test','acceptance','soak','build','run')]
    [string]$Action = 'run',
    [string]$DevRoot = 'D:\dev',
    [string]$Device = 'emulator-5554',
    [string]$ProxyUrl = $env:HTTP_PROXY
)
$ErrorActionPreference = 'Stop'
$env:ANDROID_HOME = Join-Path $DevRoot 'android-sdk'
$env:ANDROID_AVD_HOME = Join-Path $DevRoot 'android-avd'
$env:JAVA_HOME = Join-Path $DevRoot 'android-studio\jbr'
$env:GRADLE_USER_HOME = Join-Path $DevRoot 'gradle-cache'
$env:PUB_CACHE = Join-Path $DevRoot 'pub-cache'
$env:Path = "$(Join-Path $DevRoot 'flutter\bin');$(Join-Path $DevRoot 'git\cmd');$(Join-Path $env:ANDROID_HOME 'platform-tools');$env:Path"
$javaTemp = Join-Path $DevRoot 'tmp'
New-Item -ItemType Directory -Force -Path $javaTemp | Out-Null
# Avoid Windows packaged-app TEMP redirection breaking Java local sockets.
# These options affect only this script and its child processes.
$env:JAVA_TOOL_OPTIONS = "-Djava.io.tmpdir=$javaTemp -Djdk.net.unixdomain.tmpdir=$javaTemp"
if ($ProxyUrl) {
    $proxy = [Uri]$ProxyUrl
    if ($proxy.Scheme -ne 'http' -or !$proxy.IsAbsoluteUri -or $proxy.UserInfo) {
        throw 'Use an absolute HTTP proxy URL without embedded credentials, or omit ProxyUrl.'
    }
    $env:JAVA_TOOL_OPTIONS += " -Dhttps.proxyHost=$($proxy.Host) -Dhttps.proxyPort=$($proxy.Port) -Dhttp.proxyHost=$($proxy.Host) -Dhttp.proxyPort=$($proxy.Port) -Dhttp.nonProxyHosts=localhost|127.*"
}
Push-Location (Join-Path $PSScriptRoot '..')
try {
    switch ($Action) {
        analyze { & flutter analyze }
        test { & flutter test }
        acceptance { & flutter test integration_test/acceptance_test.dart -d $Device --reporter expanded }
        soak { & flutter test integration_test/soak_test.dart -d $Device --reporter expanded }
        build { & flutter build apk --debug }
        run { & flutter run -d $Device }
    }
    $result = $LASTEXITCODE
} finally { Pop-Location }
exit $result
