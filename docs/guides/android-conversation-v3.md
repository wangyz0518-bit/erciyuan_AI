# Android 连续语音测试版

> 状态：开发联调，真机声学验收待完成
> 日期：2026-11-18
> 关联：会话 v3、Android Flutter PoC

Android 调试构建通过 `MODEL_GATEWAY_PROTOCOL=v3` 启用新会话。文字、按住说话、连续通话共用网关的角色历史和音色绑定。原验证版的本地聊天库独立保留；v3 重连从网关恢复已保存消息。

## 启动

在连续语音工作区运行：

```powershell
./apps/windows_conversation_lab/launch.ps1 -NoBrowser
adb devices
adb -s <device-id> reverse tcp:8788 tcp:8788
cd apps/mobile_poc
flutter run -d <device-id> --dart-define=MODEL_GATEWAY_PROTOCOL=v3 --dart-define-from-file=../../.model-local/mobile-live.json
```

启动前请关闭其他占用 v3 的 Windows 页面或 Android 会话。调试网关只监听本机回环，USB 或模拟器通过 ADB 端口转发访问。在 Windows 环境将 `JAVA_HOME` 指向 Android Studio 自带的 JBR。带本机访问令牌的调试 APK 仅供当前开发机联调。

## 验收

- 文字发送后收到角色文字和语音。切换角色、杀掉 App 后重开，检查角色与历史恢复。
- 按住说两句，松手发送。确认保存最终转写和可回听的语音消息。再按住说话并拖出按钮后松手，确认取消。
- 进入连续通话。两句话间停约两秒，确认没有提前回复。在更长停顿后接话，检查前一轮慢识别时下一句也会保留。
- 角色播放时插话，确认停播并接着回应新话。分别用外放和耳机检查回声误触发，也要验证静音、恢复、挂断和切到后台。
- 在设置的「角色声音」里切换已有音色，再发一条消息确认声音。查看消息下方的断句、转写、首字和开播估计。
- 真人说话用正常语速和柔和音量测试。Windows 数据与 Android 模拟器只能证明相应软件路径工作。

Android 的录音由 `record` 以 16 kHz 单声道 PCM 提供，连续通话请求系统回声消除及降噪。Silero v5 在本机推理，使用与 Windows 相同的模型文件（SHA-256 `2623a2953f6ff3d2c1e61740c6cdb7168133479b267dfef114a4a3cc5bdd788f`），按 32 ms 帧计算，约 160 ms 确认人声，约 2.56 秒静音结束。播放使用原生 AudioTrack，换轮时清空播放队列。播放进度依据设备播放头估算。

[会话 v3 契约](../接口/model-gateway-conversation-v3.md) · [ONNX Runtime 安装说明](https://onnxruntime.ai/docs/install/#install-on-android) · [Silero 模型与许可](https://github.com/snakers4/silero-vad/tree/v5.1.2)

## 自动验证

在 `apps/mobile_poc` 下用已授予麦克风权限的 Android 模拟器运行：

```powershell
flutter analyze
flutter test
flutter test integration_test/conversation_v3_test.dart -d <device-id> --reporter expanded
```

2026-11-18 已通过模型加载、模拟器麦克风 32 ms PCM 帧与停止、两秒停顿合一轮、前一轮转写返回前缓存下一轮、插话停播、静音恢复及录音发送/取消。后一个用例用测试服务和注入的音频检测结果控制时序。

另在隔离的真实网关运行一次文字→模型→播放→重连历史验证。此命令会调用一次云模型：

```powershell
flutter test integration_test/conversation_v3_live_test.dart -d <device-id> --reporter expanded --dart-define=MODEL_GATEWAY_PROTOCOL=v3 --dart-define=CONVERSATION_LIVE_SMOKE=true --dart-define-from-file=<isolated-config.json>
```

### 两句话停顿与播报中插话

2026-11-18 在 Android 模拟器以每包 20 ms 输入合成语音“你好，我也喜欢星星”和“想聊点什么呢”，中间停顿约两秒。App 经过正式的 32 ms 分帧、本地 Silero 检测和真实 Qwen 转写，两次运行都将“星星”和“聊”按顺序保存在同一条消息中。

| 从最后一帧人声开始计时 | 到开播 | 断句等待 | 提交到最终转写 | 最终转写到回复首字 |
| --- | --- | --- | --- | --- |
| 第一轮，播完角色回复 | 6.11 秒 | 2.57 秒 | 1.21 秒 | 0.72 秒 |
| 第二轮，播报中插话 | 6.88 秒 | 2.57 秒 | 1.17 秒 | 0.57 秒 |

第二轮在 Android AudioTrack 播放头前进后输入新语音。App 停止了旧音频，网关确认打断生效，并为新语音建立了独立输入。随后静音取消这次插话，已保存的上一轮仍在。以上是两次固定样本的实测值。真人麦克风、外放回声和实际听感仍需在手机上验证。

要复测，请把上述内容制成 `two-phrases.pcm`（16 kHz、单声道、小端有符号 PCM16，两句间静音约两秒，末尾保留至少三秒静音）。本机已生成的样本位于工作区的 `.model-local/android-v3-validation/synthetic-fixture/`。在单独终端只共享该样本目录，再从 `apps/mobile_poc` 运行测试。测试调用真实语音识别、聊天和合成服务。

```powershell
python -m http.server 8794 --bind 127.0.0.1 --directory <fixture-dir>
# 在另一个终端执行，隔离网关应已启动且已通过 adb reverse 转发其端口。
adb -s <device-id> reverse tcp:8794 tcp:8794
flutter test integration_test/conversation_v3_speech_test.dart -d <device-id> --reporter expanded --dart-define=MODEL_GATEWAY_PROTOCOL=v3 --dart-define=CONVERSATION_LIVE_PCM_PORT=8794 --dart-define-from-file=<isolated-config.json>
```
