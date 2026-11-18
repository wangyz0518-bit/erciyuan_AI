# Flutter 开发与验证指南

> 适用工程：`apps/mobile_poc/`
> Flutter：3.50.0 stable
> Dart：3.14.0（随 Flutter SDK 提供）
> Android 验证：Windows 11 x64、Android 16 / API 36、Pixel 6a 模拟器
> 状态：Android 模拟器验证通过；iOS 未验证

## 1. 工程定位

`apps/mobile_poc/` 是当前移动端本地能力验证工程，不是已经接通真实服务的正式产品版本。它用于验证 Flutter 工程、Android 构建、SQLite 本地保存、基础聊天交互、角色切换及录音播放。

当前聊天回复为模拟内容，角色为占位形象；没有真实 AI、ASR、TTS、账户或云同步。iOS 工程目录由 Flutter 模板生成，尚未在 macOS 上构建、签名或真机验证。

## 2. 环境要求

- Flutter SDK：3.50.0 stable；Dart 3.14.0 随 SDK 提供。
- Android Studio 与 Android SDK；建议安装 Android 16（API 36）平台、Platform-Tools、Build-Tools 和 Android Emulator。
- JDK：使用 Android Studio 自带运行时或兼容的 JDK 17+。
- Android 模拟器或 Android 真机。

Windows 环境搭建步骤见 [Windows 安卓开发环境搭建与验证](windows-android-setup-20261112.md)。其他平台可参考 [Flutter Android setup](https://docs.flutter.dev/platform-integration/android/setup)。

## 3. 获取依赖、运行和构建

在仓库根目录：

```powershell
Set-Location apps/mobile_poc
flutter --version
flutter doctor -v
flutter pub get
flutter devices
flutter run -d <device-id>
```

静态检查、单元测试和 Android Debug 构建：

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

APK 输出路径：

```text
build/app/outputs/flutter-apk/app-debug.apk
```

安装到指定模拟器：

```powershell
adb -s <device-id> install -r build/app/outputs/flutter-apk/app-debug.apk
```

Windows 工作站遇到 Gradle loopback 临时目录问题时，可使用工程内的 `tool/windows.ps1`。代理参数和使用方式以脚本帮助及本机网络环境为准；不要把代理地址、凭据或本机路径写入共享配置。

## 4. 自动化测试

### 快速检查

- `flutter analyze`：Dart 静态分析。
- `flutter test`：单元测试和 Widget 测试。

### Android 模拟器集成测试

需要真实 Android 模拟器：

```powershell
flutter test integration_test/acceptance_test.dart -d <device-id> --reporter expanded
flutter test integration_test/storage_failure_test.dart -d <device-id> --reporter expanded
```

GitHub Actions 的 Android Emulator Job 使用 Android API 36 / x86_64，自动执行上述两个集成测试文件，并在 Job 结束时上传模拟器 logcat（保留 7 天）。PR 和 main push 的快速检查通过后才会运行此 Job。

### 长时间连续测试

`integration_test/soak_test.dart` 是长时间连续操作测试，耗时较长，按需单独运行，不作为每次 PR 的必需检查：

```powershell
flutter test integration_test/soak_test.dart -d <device-id> --reporter expanded
```

集成测试可能重装测试应用并操作测试数据库，使用专用模拟器，不要在含有重要个人数据的安装环境中执行。

自动化文本输入不能替代真实中文输入法选词验证；模拟器播放状态不能替代人工试听确认；CI 集成测试不验证 Android 真机、iOS 或真实麦克风音质。

## 5. 验证边界

| 能力 | 当前证据 | 尚未证明 |
| --- | --- | --- |
| Android 工程 | API 36 模拟器 Debug APK 构建、安装、启动通过 | Android 真机、不同厂商设备 |
| iOS 工程 | Flutter 模板目录已生成 | macOS 构建、签名、iOS 真机 |
| 聊天 | 本地模拟回复、取消、失败重试 | 真实模型接入、流式网络请求 |
| 数据 | SQLite 本地保存及重启恢复测试 | 云同步、跨设备冲突处理 |
| 角色 | 占位形象、基础状态变化 | 正式角色素材、Live2D 产品集成 |
| 音频 | 本地录音与播放链路 | 正式 ASR/TTS、真实语音通话和音质验收 |

历史测试环境、测试步骤和结果见 [Android PoC 验证报告](../reports/android-poc-report-20261112.md)。

## 6. 工程约定

- Flutter 工程根目录为 `apps/mobile_poc/`，所有 Flutter 命令在该目录执行。
- `pubspec.yaml` 与 `pubspec.lock` 一并提交，保持依赖可复现。
- 不提交 `build/`、本地数据库、录音、设备配置、密钥和代理凭据。
- 新增依赖前先确认 Android/iOS 支持情况、维护状态和许可证。
- 涉及本地数据模型、服务端接口或跨端行为的变更，先检查相关 ADR、接口文档和调用方。
- PoC 内部数据结构不自动成为正式服务端接口契约。
