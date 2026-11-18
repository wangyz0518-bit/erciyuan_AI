# Flutter 本地验证版运行指南

> 状态：评审中
> 日期：2026-11-12
> 负责人：待定
> 关联：A/B/C/D、ADR-0001、任务 #10

`apps/mobile_poc` 是第一批七项验证使用的独立 Flutter 工程。包含聊天、角色预览、声音测试三个页面。回复是本地预设内容，头像为程序绘制的占位素材，录音和记录保存在设备本地；没有接入真实模型、语音识别、语音合成或账号系统。

## 运行

在已配置 Flutter 和 Android SDK 的终端中执行：

```powershell
cd apps/mobile_poc
flutter pub get
flutter devices
flutter run -d emulator-5554
```

当前 Windows 工作站的 Flutter、Android SDK、Android Studio、Gradle/Pub 缓存和虚拟手机数据均位于 `D:\dev`。启动模拟器可双击 `D:\dev\Start-Android-Emulator.cmd`。应用名称为“星伴验证版”。

当前工作站从桌面应用启动 Java 时，默认临时目录曾导致 `Unable to establish loopback connection`。项目提供仅影响当前进程的环境脚本：

```powershell
pwsh -File tool/windows.ps1 -Action run
pwsh -File tool/windows.ps1 -Action build
```

如依赖下载需要本机 HTTP 代理，传入 `-ProxyUrl http://127.0.0.1:7890`；脚本也会读取已有的 `HTTP_PROXY`。此地址仅是本工作站的代理示例，不是应用后台。其他工作站通过 `-DevRoot` 指定开发工具目录。脚本不修改系统代理、系统环境变量或安全设置。

## 检查和构建

```powershell
flutter analyze
flutter test
flutter test integration_test/acceptance_test.dart -d emulator-5554 --reporter expanded
flutter test integration_test/storage_failure_test.dart -d emulator-5554 --reporter expanded
flutter test integration_test/soak_test.dart -d emulator-5554 --reporter expanded
flutter build apk --debug
```

`acceptance_test.dart` 在真实安卓运行环境中检查模拟聊天、切换隔离、SQLite、角色状态及音频播放器。`soak_test.dart` 按实际经过时间执行至少 15 分钟的连续 UI 操作。运行测试时不要手动点击模拟器；录音人工测试单独安排。自动文本输入不等于中文输入法实测。

`storage_failure_test.dart` 在独立的测试数据库里用 SQLite 触发器注入写入错误，检查重开数据库后的重试、持续失败时保留草稿，以及写入期间取消。建议指定专用测试模拟器，集成测试会重新安装应用。

集成测试使用独立数据库，且仅在手动版默认数据库为空时写入 100 条明确标注的恢复测试样例。测试过程中 `flutter test` 可能重新安装测试应用；重要私人数据不要放入此原型。测试结果 JSON 写入安卓应用的 documents 目录，主机侧保存到验证证据目录。APK 位于 `build/app/outputs/flutter-apk/app-debug.apk`，不提交到 Git。

实际重启验证使用 `tool/recovery_fixture.dart` 准备空安装中的 100 条样例，再安装正常 `lib/main.dart` 入口的 APK（`adb install -r` 保留数据）。分别在准备后、进程重启后、模拟器重启后保存 SQLite 快照，以 `python tool/verify_recovery.py before.db after-app.db after-emulator.db` 比较内容。快照只包含固定样例，不应对私人数据库执行导出。Android debug 安装可用 `adb exec-out run-as dev.erciyuan.companion_poc cat databases/companion-poc.db` 导出；使用支持原生二进制重定向的终端，且先停止应用避免读到写入中的文件。

## 代码分工

| 文件 | 职责 |
| --- | --- |
| `lib/main.dart` | 三个页面、键盘布局、生命周期与媒体停止 |
| `lib/chat_controller.dart` | 模拟回复、取消、重试与角色隔离 |
| `lib/data.dart` | PoC 内部的角色与消息模型、SQLite 保存和中断恢复 |
| `lib/avatar.dart` | 占位人物、表情、活动和轻微待机动作 |
| `lib/audio_controller.dart` | 原生录音、播放、测试音、静音检测 |

数据库只服务于当前本地 PoC，不作为团队服务端接口定案。已有跨工作线接口草案保持原状；接真实后台前仍需评审数据归属、同步和字段契约。

## 手动检查

- 聊天页切换“正常”“模拟失败”“延迟 6 秒”，检查取消、重试和角色切换。
- 角色页分别操作表情、活动状态和素材缺失回退；说话状态不是精确口型。
- 声音页允许或拒绝麦克风权限；录制、保存、取消、回放。录音最长 30 秒，仅在应用缓存中保存一个片段，不上传。
- 模拟器需要接入主机麦克风才能收到声音。控制台 `adb -s emulator-5554 emu avd hostmicon` 可启用输入，完成录音后用 `hostmicoff` 关闭。此开关不能保证远程桌面已转发真实麦克风。
- 测试音只证明本地播放链路，不能证明语音合成可用。非零信号也不能代替人工确认语音清晰度。

## 平台边界

Android 模拟器的结果见验收记录；Android 真机和 iOS 构建安装仍需单独验证。iOS 目录由 Flutter 模板生成并声明了麦克风用途，尚未构建或签名，不能据此宣称苹果端通过。原生鸿蒙不在本批范围内。
