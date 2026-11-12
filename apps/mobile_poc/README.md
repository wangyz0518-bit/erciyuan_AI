# 星伴本地验证版

> 状态：评审中
> 日期：2026-11-12
> 负责人：待定
> 关联：任务 #10、第一批七项验证

Flutter 原型，包含聊天、角色预览和声音测试。聊天回复为本地模拟内容；角色为程序绘制的占位头像；SQLite、麦克风录音和音频播放使用真实设备接口。没有连接外部 AI 服务。

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
