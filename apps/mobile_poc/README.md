# 星伴本地验证版

> 状态：评审中
> 日期：2026-11-15
> 负责人：待定
> 关联：任务 #10、第一批七项验证

Flutter 沉浸聊天原型，保留角色预览和声音测试工具。未配置网关时聊天为本地模拟；配置后由 Python 后端调用 DeepSeek，完整回复后通过 CosyVoice Flash 朗读。SQLite、麦克风录音和播放使用真实设备接口；录音仍只在本机试听，不上传。

在线接口、密钥与 Android/iOS 同伴接入见 [模型网关指南](../../docs/guides/model-gateway-20261115.md)，实际结果见 [本轮报告](../../docs/reports/model-gateway-20261115.md)。

完整命令、分层和环境排障见 [运行指南](../../docs/guides/flutter-poc-guide-20261112.md)。结果与限制见 [验证报告](../../docs/reports/android-poc-report-20261112.md)。

```sh
flutter pub get
flutter run -d emulator-5554
flutter analyze
flutter test
flutter test integration_test/acceptance_test.dart -d emulator-5554 --reporter expanded
flutter test integration_test/soak_test.dart -d emulator-5554 --reporter expanded
flutter build apk --debug
```

安卓安装包为 `build/app/outputs/flutter-apk/app-debug.apk`。应用名为“星伴验证版”，包名为 `dev.erciyuan.companion_poc`。

`tool/recovery_fixture.dart` 只用于一次性测试环境的重启恢复准备：仅在空数据库中写入 100 条标明用途的样例，其中最后一条故意处于未完成状态。正式入口始终为 `lib/main.dart`，不要把测试准备入口当作交付版本。

录音仅存于本机缓存，不上传也不提交。测试应用可被测试工具重装或清除数据，不用于保存重要资料。iOS 模板尚未构建、签名或真机验证。
