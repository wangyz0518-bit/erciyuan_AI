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
