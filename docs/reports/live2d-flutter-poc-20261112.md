# Live2D Flutter 接入验证记录

> 状态：执行中，未完成项不得视为通过
> 日期：2026-11-12
> 工作线：C；基础提交：2c215dc

## 环境与来源

独立分支 `codex/live2d-flutter-poc`，独立工作目录与专用 Android API 36 x86_64 模拟器 `Flutter_Live2D_API36`。Flutter 3.50.0 / Dart 3.14.0；SDK 使用 Cubism Native R5 官方完整包。复现见 [运行指南](../guides/live2d-flutter-poc-20261112.md)。

## 原生对照示例

SDK 随附的 Android Minimum 示例已完成编译、安装与 Haru 画面显示。由于本机工具链较新，本地副本有以下适配；不能称为完全未经修改的示例复跑：

- Gradle wrapper 改用项目已有 9.5.0，AGP 从 8.9.1 改为 9.3.1，以适应本机 Java 25。
- 示例 Java toolchain 由 17 改为 25；源代码编译级别仍为示例的 Java 8。
- NDK 从 26.3.11579264 改为已安装的 28.2.13676358，CMake 仍为 3.22.1。
- R8 默认规则改为 `proguard-android-optimize.txt`。
- `LAppMinimumModel.hpp` 补充缺失的 `<functional>` 头文件。
- 只构建 x86_64 对照 APK，应用标识为 `com.live2d.demo`。

最初构建分别因 Java/Gradle 不兼容、旧 R8 配置及缺少头文件失败；修正后构建通过并显示 Haru。对照截图保留于本地 `evidence/native-sample.png`。

## Flutter 验收

Android APK 已构建，Haru 已通过 Native → EGL → Flutter Texture 显示在预览页，透明背景和 Flutter 消息叠层已目视确认。Haru 实际提供 8 个表情、6 个动作；编号保持模型原值。

首轮出现“帧计数增长但人物透明”：Cubism R5 在绘制时将纹理过滤器设为 `GL_LINEAR_MIPMAP_LINEAR`，接入层未生成 mipmap。补充 `glGenerateMipmap` 后显示正常，临时诊断色块和像素探针已移除。该问题说明帧计数不能单独证明画面成功。

模拟器使用 SwiftShader 软件渲染。初次可见画面约 9 FPS、Haru 加载约 5.3 秒；这是 Debug 模拟器观测，不满足也不用于宣称手机性能达标。功能测试末次 Haru 加载为 248 ms，渲染计数 317；冷启动与热加载不能混为一项性能结论。

| 检查 | 结果 |
| --- | --- |
| `flutter analyze` | 通过，0 issues |
| 单元测试 | 2 项通过：原音频格式检查、PCM 包络与异常输入 |
| 表情与动作命令 | 8 个表情、6 个动作均调用成功；具体情绪语义尚未定义 |
| 资源异常 | 不支持的表情、入口缺失、JSON 损坏、引用缺失均受控报错 |
| 加载卸载 | 30 轮 Haru/Mark 交替通过；每轮卸载后模型计数 0，加载后 1 |
| 渲染暂停恢复 | 20 轮通过；暂停时帧数不增长，恢复后继续增长 |
| 音频嘴部驱动 | 样例音频播放器启动成功，停止后嘴部参数回到 0；不是精确口型或听感验收 |
| 消息叠层 | 历史开关、中文/emoji/多行测试输入通过；自动输入不等于原生输入法验证 |
| 15 分钟持续操作 | 执行中 |
| 真实 Android 后台／前台切换 | 待执行 |
| 原 PoC 回归 | 待执行 |

第一轮功能测试发现历史面板的 `ColoredBox` 遮挡 `ListTile` 的 Material 绘制层，触发 Flutter 断言；改用 `Material` 后完整重跑通过。另一次测试在启动前因 ADB 短暂断连而退出，设备恢复后重跑通过。最终完整功能测试耗时约 31 秒，原始日志及 JSON 保存在本地 `acceptance.log` 和 `evidence/live2d-acceptance.json`。

## 明确未覆盖

- Android 真机上的 Profile 性能、耗电和实际音频听感。
- iOS 插件、构建、签名与真机运行。
- 正式沉浸聊天页面的实际人物替换；本轮使用独立布局测试页。
- 用户上传、ZIP 解包、模型生成、角色数据库绑定及服务端契约。
- 精确口型同步；本轮只做测试音频音量包络驱动。
