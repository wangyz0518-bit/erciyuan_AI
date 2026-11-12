> 状态：评审中
> 日期：2026-11-12
> 负责人：待定
> 关联：A、ADR-0001、[任务 #10](https://github.com/wangyz0518-bit/erciyuan_AI/issues/10)

# Windows 安卓开发环境搭建与验证

本指南适用于 Windows x64 电脑。完成后可以在安卓模拟器里运行 Flutter 官方计数器示例。以下以 `D:\dev` 为例，换盘时相应调整目录和命令。

## 1. 安装 Flutter 和 Android Studio

1. 安装 Git。打开 PowerShell，确认 `git --version` 能显示版本。[Flutter 手动安装指南](https://docs.flutter.dev/install/manual)
2. 从 Flutter SDK 归档下载 **Windows x64、stable 3.50.0**，解压到 `D:\dev\flutter`，确认该目录下有 `bin\flutter.bat`。Dart 随 Flutter SDK 提供。[Flutter SDK 归档](https://docs.flutter.dev/install/archive)
3. 下载 Android Studio，安装或解压到 `D:\dev\android-studio`。首次启动时将 **Android SDK Location** 指向 `D:\dev\android-sdk`。如已完成初始化，可在 **SDK Manager** 查看或修改 SDK 位置。[Android Studio 下载](https://developer.android.com/studio) · [Flutter 安卓安装指南](https://docs.flutter.dev/platform-integration/android/setup)

在 Android Studio 的 **SDK Manager** 中安装以下组件。需要选择具体版本时勾选 **Show Package Details**。

| 页签 | 组件 |
| --- | --- |
| SDK Platforms | Android 16.0（API 36）中的 Android SDK Platform 36 |
| SDK Tools | Android SDK Command-line Tools、Android SDK Platform-Tools、Android Emulator、Android SDK Build-Tools 36.0.0、NDK (Side by side) 28.2.13676358 |

系统镜像在创建虚拟设备时下载。首次安装和编译需要联网获取 SDK、Gradle 和 Dart 依赖。

## 2. 配置本机路径

在 Windows 的**用户环境变量**中设置下表内容。往 `Path` 添加新条目时保留原有条目。配置后重新打开 PowerShell 和 Android Studio。

| 变量 | 示例值 | 用途 |
| --- | --- | --- |
| `Path` | `D:\dev\flutter\bin` 和 `D:\dev\android-sdk\platform-tools` | 使用 `flutter` 和 `adb` 命令 |
| `ANDROID_HOME` | `D:\dev\android-sdk` | 指向安卓 SDK |
| `ANDROID_AVD_HOME` | `D:\dev\android-avd` | 将虚拟设备数据放在指定磁盘，创建模拟器前先建好目录 |
| `GRADLE_USER_HOME`（可选） | `D:\dev\gradle-cache` | 将 Gradle 缓存放在指定磁盘 |
| `PUB_CACHE`（可选） | `D:\dev\pub-cache` | 将 Dart 包缓存放在指定磁盘 |

[Android 环境变量说明](https://developer.android.com/tools/variables)

在 PowerShell 中执行下面的命令。这里使用 Android Studio 自带的 Java（`jbr`）。

```powershell
$androidStudio = 'D:\dev\android-studio'
flutter config --android-sdk "$env:ANDROID_HOME" --android-studio-dir "$androidStudio" --jdk-dir "$androidStudio\jbr"
flutter --version
flutter doctor --android-licenses
flutter doctor -v
```

阅读并按提示确认 Android SDK 许可。检查 `flutter doctor -v` 的 **Android toolchain** 一项是否通过，以及 SDK、Java 路径是否正确。Chrome 和 Visual Studio 对应网页和 Windows 桌面开发，复跑本指南时只需安卓工具链通过。

## 3. 创建并启动安卓模拟器

1. 检查虚拟化加速。在 PowerShell 执行 `& "$env:ANDROID_HOME\emulator\emulator.exe" -accel-check`。本次验证返回 `WHPX ... is installed and usable`。如果不可用，按官方说明检查固件虚拟化和 Windows Hypervisor Platform。启用 Windows 功能后按系统提示安排重启。[安卓模拟器硬件加速](https://developer.android.com/studio/run/emulator-acceleration)
2. 在 Android Studio 的 **Device Manager** 创建虚拟设备。选择 **Pixel 6a**，下载并选择 **Android 16（API 36）、Google APIs、x86_64** 系统镜像，保存后点击启动。也可从欢迎界面的 **More Actions → Virtual Device Manager** 进入。[安卓虚拟设备管理](https://developer.android.com/studio/run/managing-avds)
3. 等待安卓桌面出现。在 PowerShell 运行 `flutter devices`，记下安卓模拟器的 ID，例如 `emulator-5554`。如有多个设备，下面用 `adb -s` 指定该 ID。

## 4. 编译、安装并运行官方示例

把示例建在仓库外的新目录。将 `$emulatorId` 改成上一步看到的 ID。首次编译要下载依赖，耗时可能较长。

```powershell
$samplePath = 'D:\dev\flutter_android_verify_20261112'
$emulatorId = 'emulator-5554'

flutter create --platforms=android --org dev.local --project-name flutter_android_verify $samplePath
Set-Location -LiteralPath $samplePath
flutter build apk --debug
adb -s $emulatorId install -r .\build\app\outputs\flutter-apk\app-debug.apk
adb -s $emulatorId shell am start -W -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -n dev.local.flutter_android_verify/.MainActivity
```

逐条运行，上一条成功后再继续。安装成功时会显示 `Success`。应用打开后应看到 `Flutter Demo Home Page`，初始数字是 `0`。点三次右下角的 `+`，确认数字变为 `3`。

要检查应用完全退出后能否再次打开，可以运行下面两条命令，也可以停止应用后从模拟器的应用列表打开 `flutter_android_verify`。示例重开后计数从 `0` 开始。

```powershell
adb -s $emulatorId shell am force-stop dev.local.flutter_android_verify
adb -s $emulatorId shell am start -W -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -n dev.local.flutter_android_verify/.MainActivity
```

## 常见问题

- **Flutter 找不到安卓 SDK 或 Java**。核对 Android Studio 的 SDK Location、`ANDROID_HOME` 和 `flutter doctor -v` 显示的 Java 路径，再执行第 2 节对应的配置命令。
- **模拟器显示 `offline`**。先等安卓完成首次开机，再运行 `flutter devices`。图形驱动不兼容时，可以在 Device Manager 将 Graphics 改为 Software 并重新启动模拟器。[安卓模拟器图形设置](https://developer.android.com/studio/run/emulator-acceleration#configure-graphics-acceleration)
- **Gradle 报 `Unable to establish loopback connection`**。本次在 Codex 启动的 Windows 终端中遇到该错误，将 Java 的临时目录指到本机可写的短路径后通过。在同一个 PowerShell 窗口运行以下命令，再重试编译。这项设置随终端关闭而失效。

  ```powershell
  $javaTemp = 'D:\dev\tmp'
  New-Item -ItemType Directory -Path $javaTemp -Force | Out-Null
  $env:JAVA_TOOL_OPTIONS = "$env:JAVA_TOOL_OPTIONS -Djava.io.tmpdir=$javaTemp -Djdk.net.unixdomain.tmpdir=$javaTemp".Trim()
  ```

- **Gradle 下载超时**。检查本机能否访问 Gradle、Google Maven 和 Maven Central。如果网络需要代理，按 Gradle 官方说明配置在本机的 Gradle 用户目录，代理地址和凭据保留在本机。[Gradle 网络配置](https://docs.gradle.org/current/userguide/networking.html#sec:accessing_the_web_via_a_proxy)

## 验证记录

- 日期为 2026-11-12。使用 Windows 11 25H2 x64、Flutter 3.50.0 stable（`ab2912035e`）、Dart 3.14.0、Android Studio 自带 OpenJDK 25.0.4。
- Android SDK Platform / Build-Tools 为 API 36 / 36.0.0，Command-line Tools 为 22.0，Platform-Tools 为 37.0.3，NDK 为 28.2.13676358。模拟器为 37.2.13.0，镜像为 Android 16（API 36）、Google APIs、x86_64、修订版 7。
- 在已安装工具链的电脑上新建官方示例并复跑，使用现有依赖缓存。

| 检查项 | 结果 |
| --- | --- |
| Flutter 安卓工具链 | `flutter doctor -v` 的 Android toolchain 通过，Android SDK 许可已接受 |
| 虚拟设备 | WHPX 可用，`flutter devices` 识别到独立的 Pixel 6a 验证模拟器 `emulator-5562` |
| 编译和安装 | `flutter build apk --debug` 成功，ADB 安装返回 `Success` |
| 启动和操作 | 应用打开到 `Flutter Demo Home Page`。计数初始为 0，点击三次后为 3 |
| 退出和重开 | 强制停止后重新启动成功，计数回到 0，符合官方示例行为 |

Android 真机、iOS 和项目功能的验证由 [任务 #10](https://github.com/wangyz0518-bit/erciyuan_AI/issues/10) 跟踪。
