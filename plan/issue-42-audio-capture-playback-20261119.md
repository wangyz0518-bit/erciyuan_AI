# Issue #42 正式音频底座实施与验收

2026-11-19。正式代码为 apps/mobile；保留已有 apps/mobile_poc，不复制历史会话或 PoC 数据结构。

## 复用来源与边界

- PR #16 的本机录音、试听、权限与取消策略，适配为 RecordAudioCapture + DeviceAudioFilePlayback。
- PR #22 的 PcmPlayer.kt 已移植到 Android MainActivity FlutterEngine 生命周期。Dart AndroidPcmPlayback 限定 24 kHz/16-bit/mono、≤192000 字节分片和有效 streamId。iOS 没有原生 PCM，不能假称支持；正式跨端基础使用 WAV 文件播放。
- 当前 pubspec 依赖 record 7.2、audioplayers 6.8、path_provider 2.1，须经 Flutter CI 的 pub get、analyze、test、APK 构建实际验证。三方原始许可和转授权范围需按发布流程持续审查。
- 新增独立页面范围 AudioSessionController：异步权限/启动完成前若取消，利用 epoch + 串行资源操作丢弃迟到结果；录音完成只展示本机试听按钮，**不入 raw_events、不请求模型、不自动上传或转写**。
- 录音暂存于应用缓存。用户取消、滑出、切人物、页面退出或应用进入后台时删除；不承诺手机进程被系统强杀后的立即清理，之后需追加过期缓存清扫。
- 真实麦克风输入、权限拒绝提示、音质/设备播放、iOS 构建与 Android 真机体验必须提供平台实测证据；单元测试/Android 模拟器不能替代。

## 验收检查

1. 单元测试：拒绝授权、快速松开、正常录/放/删除、页面切换/后台撤销、销毁中迟到的权限回调。
2. Flutter analyze/test；Android Debug APK 与模拟器回归；单独 iOS Simulator CI（Issue #40）。
3. 手工 Android 和 iPhone：前后台中断、权限撤销、试听、静音、PCM 开始/结束/停止与实际播放无尾音。
4. 未跑的人工测试保持未验收，Issue 的最终关闭以全部验收条件为准。

## 2026-11-19 存储空间与长按边界补充

录音控制器增加默认 60 秒最大时长（供测试注入较短上限）。达到上限则在页面范围内调用正常本机 stop，生成可试听但仍未发送的临时 WAV；松手晚于超时不再删除已保存试听文件。重复停止命令不重复调用底层录音器；取消、角色切换、后台和页面退出则清除录音截止计时器。对应新增三项假端口回归，绝不将本机时长测试宣称为实际麦克风/权限/设备音质验收。


## 2026-11-19 iOS 原生 PCM 可复用增量（独立 PR）

- 从仓库现有 `apps/mobile_poc/ios/Runner/ConversationPlayer.swift`（交付提交 `8d556655`）选择性移植 AVAudioEngine 的 PCM16LE 24 kHz 单声道播放器。该代码是仓库内既有 PoC；**未移植** ONNX Runtime、Silero、外部模型、连续语音对话或任何供应商凭据。
- 正式 `apps/mobile/ios` 的 Flutter engine 注册 `dev.erciyuan/pcm`，Xcode Runner Sources 纳入 Swift 文件。Flutter `NativePcmPlayback` 在 Android 与 iOS 共用 `start/append/end/stop` 协议；维持旧类型名别名以减少调用方破坏。
- Flutter 方法通道新增过时流拒绝、输入边界、异步 start 被 stop 打断时重新停止原生播放等回归。没有将音频自动保存成聊天消息。
- **验证边界**：Flutter CI、Android APK/模拟器可验证 Dart 适配，但 Android 不能验证新增 iOS Swift 源码。iOS macOS CI 实际进入 Xcode 构建并成功、iPhone 真机外放、音频路由/中断/停止后无尾音均需要独立证据；在这些证据前不能关闭 #42。


## 2026-11-19 iOS Simulator CI runner 调整

- 首次 PR #70 macOS job 的实际日志证明 Swift/Flutter iOS Simulator 构建成功、Runner 安装启动和截图成功，`acceptance_test.dart` 全部通过；随后单独启动第二个 `flutter test` 进程后，Xcode build 完成但测试 runner 未返回任何用例输出，最终 job 被 60 分钟限制取消。不能把它记为完整 iOS CI 通过。
- 为避免同一模拟器连续启动两个 Flutter integration-test runner，`run_ios_simulator_ci.sh` 已改为一次执行 `flutter test integration_test`，同时为单项测试设 5 分钟 timeout、整组设 20 分钟 Python subprocess timeout。这样如再挂起会有可诊断的明确失败，不再消耗整小时。
- 最新 PR #70 CI：Flutter 官方验证已 success；Android 模拟器仍运行；更新后的 macOS iOS Simulator job 已排队，尚无新测试结果。只有实际 job 结束且成功后，才记录本次 iOS 模拟器完整回归通过。
- 本次不进行物理手机录音/播放/音频路由或人工听感验收；这些全部由下一阶段 #78 执行。流式 PCM 真实 TTS 调用方和供应商音频流联调在 #79 范围。

### 模拟器原生 PCM 方法通道回归

- 新增 `integration_test/native_pcm_playback_test.dart`，在 Android/iOS 模拟器上通过正式 `dev.erciyuan/pcm` MethodChannel 发送 24 kHz、16-bit、mono 的合成测试波形，检查原生 sink 可接收、排空并报告帧数。
- Android/iOS 模拟器脚本均改为单次执行整个 `integration_test` 目录，并设置单项/整组超时，覆盖 SQLite/UI、失败事务和原生 PCM 三组测试。
- 该回归验证的是模拟器的原生调用链和 PCM 队列，不是物理手机音频路由、耳机/蓝牙、真实麦克风或人工听感；这些仍由 #78 验收。


### 2026-11-19 headless emulator PCM finding

- The first combined Android emulator run built the app and passed the existing SQLite/UI integration cases. The new native PCM test successfully completed `start` and `append`, but timed out waiting for native `end` to report a drained playback head.
- Runner log also reports PulseAudio could not initialize. This hosted emulator has no usable audio output clock; treating its lack of playback-head advancement as a product playback failure would conflate a headless test environment with device behavior.
- The native simulator test is therefore narrowed to prove the real platform MethodChannel can start, accept a bounded 24 kHz PCM packet and stop/release the stream. It does **not** claim audible playback or drain success. `end`/drain, audible output, route and interruption behavior require an audio-capable physical device and remain in #78.
- Flutter unit tests continue to cover the Dart `end` protocol and stale/invalid stream handling using a deterministic mocked channel. The next Android/iOS CI run must still prove native compilation and start/append/stop on both simulators.
