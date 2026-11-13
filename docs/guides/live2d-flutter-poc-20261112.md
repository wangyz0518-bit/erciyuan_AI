# Live2D Flutter 本地接入验证

> 状态：Android 本地验证可用，验收范围与证据缺口另见报告
> 日期：2026-11-12
> 工作线：C；关联 #10

## 范围

在 `apps/mobile_poc` 增加独立入口 `lib/main_live2d.dart`，使用 `packages/live2d_avatar` 将 Cubism Native R5 的 OpenGL ES 渲染结果放进 Flutter Texture。Android 验证应用标识为 `dev.erciyuan.companion_poc.live2d`；原 PoC 使用 `poc` flavor 和原标识。验证页只使用固定样例，不打开聊天数据库，不改变角色绑定或服务端接口。

首轮只实现 Android 的 x86_64、arm64-v8a。iOS 没有插件实现，调用会明确提示未支持；不能将 Android 结果解释为双端通过。现有沉浸聊天界面由另一分支开发，本页用独立消息、侧栏和历史面板测试组合效果，尚未替换正式聊天页的人物。

## 依赖与准备

已使用 Flutter 3.50.0 / Dart 3.14.0、Android SDK API 36、NDK 28.2.13676358、CMake 3.22.1。Android Studio 的 Java 25 用于 Gradle；插件 Java 编译目标为 17。

从仓库根目录运行：

```powershell
pwsh -File apps/mobile_poc/tool/live2d.ps1 -Action prepare
pwsh -File apps/mobile_poc/tool/live2d.ps1 -Action build
pwsh -File apps/mobile_poc/tool/live2d.ps1 -Action run -Device emulator-5580
```

脚本支持 `-DevRoot` 和可选 `-ProxyUrl`，只设置当前进程环境。准备步骤下载官方发行包并校验 SHA-256，将 SDK 保留在 `.local/live2d/sdk/`，把 Haru、Mark 和着色器复制到被 Git 忽略的本地资源目录。SDK、模型、生成 APK 不提交。首次准备前阅读下方对应条款；后续不自动升级依赖。

脚本不创建模拟器。先按现有 Windows Android 指南启动设备，用 `adb devices` 确认编号，再传入 `-Device`。本次专用设备为 API 36 x86_64、SwiftShader、720×1280，编号 `emulator-5580`；真实手机通常使用自己的序列号。

- 发行包：`CubismSdkForNative-5-r.5.zip`（官方稳定版 R5）。
- 地址：<https://cubism.live2d.com/sdk-native/bin/CubismSdkForNative-5-r.5.zip>
- SHA-256：`7ff3a4bbc19c0a8728965aa522ab77eb11b252916453e68a8a78d3b71188bb12`。
- 模型：同包 `Samples/Resources/Haru`、`Samples/Resources/Mark`，使用其 `model3.json`、MOC3、纹理、表情、动作和物理文件。
- 测试音频：同包 `Haru/sounds/haru_talk_13.wav`，不是用户录音或语音合成结果。

SDK 包中的 Core、Framework 和模型保持配套。官方原生示例的本地构建适配记录在验收报告中；插件直接引用 SDK Framework 和 Core，没有改写这两部分。

## 组件试验接口

这是 C 线本地接口草案，不替代 `docs/接口/` 的跨工作线契约。

| 操作 | 含义 |
| --- | --- |
| `create()` | 建立纹理和渲染线程，得到 Texture ID |
| `load(asset)` | 检查打包资源及 MOC3 一致性；返回表情、动作、`lipSyncParameters`、真实参数 `parameters`（最小／最大／默认值）及外形分组 `poseParts`；加载失败保留原模型 |
| `command('expression', value: id)` | 播放模型自带表情，不把 F01 等编号擅自命名为业务情绪 |
| `command('motion', value: 'group:index')` | 播放模型自带动作 |
| `command('mouth', number: 0…1)` | 嘴部开合；音频包络按播放器实际位置驱动 |
| `command('zoom'/'x'/'y', number: value)` | 取景缩放和平移，不能生成模型缺失的身体部分 |
| `setPose(values, parts: selections)` | 进入手动调姿，保持当前姿态并批量更新指定参数和外形；按模型实际范围钳制，未知 ID 拒绝整批操作 |
| `command('automaticPose')` | 退出手动姿态并恢复模型自动动作和物理效果；播放动作或表情也会进入自动模式 |
| `setActive(value)` | 暂停／恢复渲染，并清除嘴部状态 |
| `unload()` | 释放模型及纹理，保留渲染器供重新加载 |
| `stats()` | 帧数、加载耗时、实例数、恢复次数、渲染错误、当前参数、外形选项和手动状态 |
| `close()` | 异步释放模型、EGL、SurfaceProducer 和线程；必须等待完成后才能创建下一实例 |

本轮限一个活动实例。Native 操作统一在一个 HandlerThread 执行；渲染失败通过统计反馈，不显示成功状态。Surface 被系统回收时释放 GL 状态，重建后按原模型路径重新加载。模型使用本地受控样例；这不是任意不可信 ZIP 的上传入口。

## 操作与检查

- 默认打开纯人物视图。右上角聊天图标可切换测试消息、历史和输入框，调节图标可收起面板。
- 在“部位”页选择分组并滚动查看所有滑块。调整滑块会进入手动调姿，停住当前自动动画和物理摆动。可同时调整头、躯干、手臂等部位。数值是模型参数值，外形和活动范围由模型决定。
- Haru 的“手臂”和“手腕与手型”分组提供左、右臂 A/B 外形切换。B 臂及对应手腕、手型需要在适用外形下观察。Mark 的“腿部”可控制左右腿。
- 点参数旁的圆形箭头复位单项，点“重置部位”复位当前分组。顶栏圆形箭头恢复整个人物、外形和默认全身取景。
- “动作”页可点击模型自带动作、表情及样例音频。Haru 有 8 个表情、6 个动作及嘴部映射；Mark 有 6 个动作，支持手动嘴部开合，样例音频在该模型上仅播放声音。
- 右侧模式按钮可在自动动作和手动调姿之间切换。切换模型会清除手动姿态、更新可选部位，并恢复自动动作。
- “取景”页支持缩放和平移，并可开关拖动转头。按住人物拖动可调转头及抬头，松手保持姿态。人物右侧按钮可切换全身／半身，侧栏可切换 Haru／Mark。

```powershell
pwsh -File apps/mobile_poc/tool/live2d.ps1 -Action analyze
pwsh -File apps/mobile_poc/tool/live2d.ps1 -Action test
pwsh -File apps/mobile_poc/tool/live2d.ps1 -Action acceptance -Device emulator-5580
pwsh -File apps/mobile_poc/tool/live2d.ps1 -Action soak -Device emulator-5580
pwsh -File apps/mobile_poc/tool/live2d.ps1 -Action regression -Device emulator-5580
```

`acceptance`、`soak`、`regression` 使用 Flutter 官方支持的 Android instrumentation 方式：构建测试入口和 AndroidTest APK，在指定设备通过 `AndroidJUnitRunner` 执行，无需桌面 DDS 连接。脚本检查 JUnit 成功结果并取回 JSON；`regression` 包含原聊天验收和三个 SQLite 故障用例。测试应用保留安装，完成后用 `-Action run` 恢复正常验证入口。

使用专用模拟器，测试期间不要手动操作。统计 JSON 位于测试应用 documents 目录，脚本自动复制到 `.local/live2d/evidence/`。持续操作测试按真实经过时间至少 15 分钟执行；逐轮进度可从 `adb -s emulator-5580 logcat -s flutter:I` 查看。

普通 PoC 的默认 flavor 是 `poc`；本分支增加了插件依赖，因此构建前也需要完成 `prepare`。插件构建只启用 arm64-v8a 和 x86_64，不包含 ARMv7。

## 来源与使用边界

样例和 SDK 的权利归其原作者；它们不是本项目原创人物。准备脚本不向第三方上传数据。

- [官方 Native SDK](https://www.live2d.com/en/sdk/download/native/)
- [Haru 官方说明](https://www.live2d.com/en/learn/sample/haru/)
- [Core 软件条款](https://www.live2d.com/eula/live2d-proprietary-software-license-agreement_en.html)
- [Framework 开放软件条款](https://www.live2d.com/eula/live2d-open-software-license-agreement_en.html)
- [免费素材条款](https://www.live2d.com/eula/live2d-free-material-license-agreement_en.html)
- [模型单独条款](https://www.live2d.com/eula/live2d-sample-model-terms_en.html)

本次完成本地技术试验；正式发布及允许用户导入模型的产品授权仍需按产品形式确认。
