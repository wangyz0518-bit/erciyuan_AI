param(
  [ValidateSet('prepare','analyze','test','build','run','acceptance','idle-acceptance','demo-build','demo-run','demo-acceptance','package-fixture','package-acceptance','soak','regression')]
  [string]$Action='run',
  [string]$DevRoot='D:\dev',
  [string]$Device='emulator-5580',
  [string]$ProxyUrl=$env:HTTP_PROXY
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$app=Join-Path $repo 'apps/mobile_poc'
$local=Join-Path $repo '.local/live2d'
$sdk=Join-Path $local 'sdk/CubismSdkForNative-5-r.5'
$env:ANDROID_HOME=Join-Path $DevRoot 'android-sdk'
$env:ANDROID_AVD_HOME=Join-Path $DevRoot 'android-avd'
$env:JAVA_HOME=Join-Path $DevRoot 'android-studio/jbr'
$env:GRADLE_USER_HOME=Join-Path $DevRoot 'gradle-cache'
$env:PUB_CACHE=Join-Path $DevRoot 'pub-cache'
$env:Path="$(Join-Path $DevRoot 'flutter/bin');$(Join-Path $DevRoot 'git/cmd');$env:Path"
$javaTemp=Join-Path $DevRoot 'tmp'
New-Item -ItemType Directory -Force $javaTemp,$local | Out-Null
$env:JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$javaTemp -Djdk.net.unixdomain.tmpdir=$javaTemp"
if($ProxyUrl){
  $proxy=[Uri]$ProxyUrl
  if($proxy.Scheme -ne 'http' -or !$proxy.IsAbsoluteUri -or $proxy.UserInfo){throw 'Use an absolute HTTP proxy URL without credentials'}
  $env:JAVA_TOOL_OPTIONS+=" -Dhttps.proxyHost=$($proxy.Host) -Dhttps.proxyPort=$($proxy.Port) -Dhttp.proxyHost=$($proxy.Host) -Dhttp.proxyPort=$($proxy.Port) -Dhttp.nonProxyHosts=localhost|127.*"
}
function Invoke-AndroidSuite([string]$TestFile, [string]$ReportName) {
  $target=Join-Path $app "integration_test/$TestFile"
  Push-Location (Join-Path $app 'android')
  try {
    & ./gradlew.bat :app:assembleLive2dDebug :app:assembleLive2dDebugAndroidTest "-Ptarget=$target" '-Ptarget-platform=android-arm64,android-x64' --console plain
    if($LASTEXITCODE -ne 0){throw 'Android test build failed'}
  } finally { Pop-Location }
  $adb=Join-Path $env:ANDROID_HOME 'platform-tools/adb.exe'
  foreach($apk in @('build/app/outputs/apk/live2d/debug/app-live2d-debug.apk','build/app/outputs/apk/androidTest/live2d/debug/app-live2d-debug-androidTest.apk')){
    & $adb -s $Device install -r $apk
    if($LASTEXITCODE -ne 0){throw "Test APK installation failed: $apk"}
  }
  # A successful run must produce a new report, not reuse an earlier result.
  & $adb -s $Device shell run-as dev.erciyuan.companion_poc.live2d rm -f "app_flutter/$ReportName"
  if($LASTEXITCODE -ne 0){throw 'Could not reset the synthetic test report'}
  $result=& $adb -s $Device shell am instrument -w dev.erciyuan.companion_poc.live2d.test/androidx.test.runner.AndroidJUnitRunner
  $result | Write-Output
  if($LASTEXITCODE -ne 0 -or ($result -join "`n") -notmatch 'OK \([1-9]\d* tests?\)'){throw 'Android instrumentation suite failed; inspect output above'}
  $evidence=Join-Path $local 'evidence'
  New-Item -ItemType Directory -Force $evidence | Out-Null
  & $adb -s $Device shell run-as dev.erciyuan.companion_poc.live2d cat "app_flutter/$ReportName" | Set-Content (Join-Path $evidence $ReportName)
  if($LASTEXITCODE -ne 0){throw 'Could not collect test evidence'}
}
Push-Location $app
try {
  if($Action -eq 'prepare'){
    # The approved development setup uses the official SDK under its accompanying terms.
    $zip=Join-Path $local 'CubismSdkForNative-5-r.5.zip'
    if(!(Test-Path $zip)){
      Invoke-WebRequest 'https://cubism.live2d.com/sdk-native/bin/CubismSdkForNative-5-r.5.zip' -OutFile $zip
    }
    $expected='7FF3A4BBC19C0A8728965AA522AB77EB11B252916453E68A8A78D3B71188BB12'
    if((Get-FileHash $zip).Hash -ne $expected){throw 'SDK archive hash mismatch'}
    if(!(Test-Path "$sdk/Core/include/Live2DCubismCore.h")){Expand-Archive $zip (Join-Path $local 'sdk')}
    New-Item -ItemType Directory -Force assets/live2d | Out-Null
    foreach($model in @('Haru','Mark')){
      Copy-Item "$sdk/Samples/Resources/$model" assets/live2d -Recurse -Force
    }
    $shaders=Join-Path $repo 'packages/live2d_avatar/android/src/main/assets/live2d_shaders'
    New-Item -ItemType Directory -Force $shaders,assets/live2d/fixtures | Out-Null
    Copy-Item "$sdk/Framework/src/Rendering/OpenGL/Shaders/StandardES/*" $shaders -Recurse -Force
    '{invalid json' | Set-Content assets/live2d/fixtures/broken.model3.json
    '{"Version":3,"FileReferences":{"Moc":"missing.moc3","Textures":["missing.png"]}}' | Set-Content assets/live2d/fixtures/missing.model3.json
    & flutter pub get
  } else {
    if(!(Test-Path "$sdk/Core/include/Live2DCubismCore.h")){throw 'Run -Action prepare first'}
    switch($Action){
      analyze { & flutter analyze }
      test { & flutter test }
      build { & flutter build apk --debug --flavor live2d -t lib/main_live2d.dart --target-platform android-x64,android-arm64 }
      run { & flutter run --flavor live2d -t lib/main_live2d.dart -d $Device }
      acceptance { Invoke-AndroidSuite 'live2d_test.dart' 'live2d-acceptance.json' }
      idle-acceptance { Invoke-AndroidSuite 'dragon_idle_test.dart' 'dragon-idle-acceptance.json' }
      demo-build { & flutter build apk --debug --flavor live2d -t lib/main_avatar_demos.dart --target-platform android-x64,android-arm64 }
      demo-run { & flutter run --flavor live2d -t lib/main_avatar_demos.dart -d $Device }
      demo-acceptance { Invoke-AndroidSuite 'avatar_demos_test.dart' 'avatar-demos-smoke.json' }
      package-fixture { Invoke-AndroidSuite 'avatar_package_fixture_test.dart' 'avatar-package-fixture.json' }
      package-acceptance { Invoke-AndroidSuite 'avatar_package_test.dart' 'avatar-package-acceptance.json' }
      soak { Invoke-AndroidSuite 'live2d_soak_test.dart' 'live2d-soak.json' }
      regression { Invoke-AndroidSuite 'live2d_regression_test.dart' 'acceptance-results.json' }
    }
  }
  $code=$LASTEXITCODE
}finally{Pop-Location}
exit $code
