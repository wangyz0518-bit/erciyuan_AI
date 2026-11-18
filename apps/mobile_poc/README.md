# Flutter 本地能力验证工程

> 类型：PoC / 工程基线
> 状态：Android 模拟器验证通过；iOS 尚未验证
> 关联：[Issue #10](https://github.com/wangyz0518-bit/erciyuan_AI/issues/10)

本工程用于验证 Flutter 移动端的基础交互与设备能力，并作为后续正式产品工程演进的起点。当前包含：

- 聊天页面：本地模拟回复、取消、失败重试和角色隔离。
- 本地数据：SQLite 保存角色、消息和偏好，支持重启恢复。
- 角色展示：程序绘制的占位形象和基础状态变化。
- 音频：设备录音、播放和临时文件管理。
- 自动化：单元测试、集成验收和存储故障测试。

**当前边界：** 未接入真实 AI、ASR、TTS、账户或云端同步；占位角色不代表正式素材。iOS 工程由 Flutter 模板生成，尚未构建、签名或真机验证。

## 开发命令

在本目录执行：

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run
```

Android 模拟器集成测试（需先启动模拟器）：

```sh
flutter test integration_test/acceptance_test.dart -d <device-id> --reporter expanded
flutter test integration_test/storage_failure_test.dart -d <device-id> --reporter expanded
```

长时间 soak 测试按需单独执行，不作为每次提交的快速检查：

```sh
flutter test integration_test/soak_test.dart -d <device-id> --reporter expanded
```

Windows 环境辅助脚本见 [tool/windows.ps1](tool/windows.ps1)。完整环境说明、测试边界和排障方法见 [Flutter 开发与验证指南](../../docs/guides/flutter-poc-guide-20261112.md)。

Debug APK 输出到 `build/app/outputs/flutter-apk/app-debug.apk`，属于本地构建产物，不提交 Git。

## GitHub Actions Android 模拟器集成测试

`.github/workflows/flutter-android.yml` 在现有格式、分析、unit/widget 和 Debug APK 快速检查成功后，使用 API 36 / x86_64 / Google APIs 模拟器自动运行 `acceptance_test.dart` 与 `storage_failure_test.dart`。两个测试在 `apps/mobile_poc/` 下执行，并保留最多 7 天的 `android-emulator-logcat` 诊断产物；不上传测试数据库、录音或真实用户数据。

CI 使用 `bash tool/run_android_integration_ci.sh` 在同一 Shell 中执行测试并在退出时收集日志。该脚本仅用于 GitHub Actions 临时模拟器，开发者本地应继续使用上文的 `flutter test ... -d <device-id>` 命令。长时 soak test 仍为手动执行。Android 模拟器通过不代表真实 Android 设备或 iOS 已通过。
