# 移动端技术方案调研

> 状态：调研报告，供技术选型讨论，不代表团队已定案。
> 日期：2026-11-11
> 范围：Android/iOS 客户端框架、跨端方案、移动端本地核心（Go/Rust），以及与本项目相关的形象、语音、聊天能力。

## 1. 结论摘要

1. **原生 Kotlin + Jetpack Compose 仍是 Android 的主流**；跨端新项目以 Flutter 和 React Native 为主，二者是事实上的双寡头。
2. **本项目第一阶段建议优先评估 Flutter**：一套 UI 覆盖 Android/iOS，动画和渲染可控，适合聊天、语音、形象展示这类交互密集型界面。若团队 React/TypeScript 基础更强，或鸿蒙是近期硬需求，则改选 **React Native + Expo**。
3. **不建议第一阶段直接上 KMP/Compose Multiplatform**：学习和工具链成本高，生态较小，等业务核心稳定后再评估抽取共享层。
4. **鸿蒙不作为第一阶段目标**：HarmonyOS NEXT 不兼容 Android APK，必须专门适配；真要做时优先评估 RNOH、Kuikly 或原生 ArkTS。
5. **Go/Rust 可以做移动端“本地后端”，但形态是编译成库嵌入 App**，不是独立进程；Rust 的移动端工具链更成熟，Go 可复用但官方仍标注 experimental。
6. **UI 与业务核心必须分层**：协议、数据模型、对话调度独立于 UI，未来换框架或加端时不用重写业务。

## 2. 调研方法

- 抽查 38 个公开开源 Android 应用的默认分支，读取构建文件、统计源码文件数和 `res/layout` 数量，判断 UI 技术栈。
- 查阅 Flutter、React Native、JetBrains Compose Multiplatform、Kuikly 等官方文档与 Showcase。
- 市场指标：GitHub Stars、npm 周下载量、公开开发者调查与企业案例。
- 局限：静态代码判断，未逐个编译运行；部分项目多模块混合，按主 App 归类；市场份额为定性判断，不引用单一付费报告的具体百分比。

## 3. 开源 Android 应用技术栈盘点

### 3.1 Kotlin + Jetpack Compose（新一代主流）

| 应用 | 技术栈 | 说明 |
| --- | --- | --- |
| Signal | Kotlin + Compose + Media3 | 新界面大量 Compose，仍有 500+ XML layout，渐进迁移 |
| Thunderbird / K-9 Mail | Kotlin + Compose + KMP | 邮件客户端重写后以 Compose 为主 |
| Element X | Kotlin + Compose + Rust SDK | 完全 Compose，核心交给 Rust |
| Bitwarden | Kotlin + Compose | 基本纯 Compose，向 KMP 迁移 |
| F-Droid 客户端 | Kotlin + Compose + KMP | 从 Java/Views 迁移 |
| Seal | Kotlin + Compose | 无 XML 布局 |
| Feeder | Kotlin + Compose | 从 Java 版重写 |
| Home Assistant | Kotlin + Compose | 主界面 Compose |
| Tailscale | Kotlin + Compose | 纯 Compose |
| Magisk | Kotlin + Compose | 原生 API 与 Compose 结合 |
| KDE Connect | Kotlin + Compose | 已迁移 |
| Neo-Launcher / Lawnchair | Kotlin + Compose + 部分 Java | 启动器，混合代码 |
| Florisboard | Kotlin + Compose + KMP | 输入法，较激进的 Compose 使用 |
| ReadYou | Kotlin + Compose | 新项目典型 |

### 3.2 Kotlin/Java + XML Views（传统方案，数量最多）

| 应用 | 技术栈 | 依据 |
| --- | --- | --- |
| Telegram | Java 为主 + C++ + 自绘 View | 不用 Jetpack 生态，UI 自绘 |
| NewPipe | Java/Kotlin + XML Views + Media3 | 116 个 layout；shared 模块刚开始用 Compose Multiplatform |
| AntennaPod | Java 为主 + XML Views | 118 个 layout；仅 Wear OS 版用 Compose |
| LibreTube | Kotlin + ViewBinding + Media3 | 94 个 layout，不是 Compose |
| VLC for Android | Java/Kotlin + NDK + libVLC | 202 个 layout + C 内核 |
| OsmAnd | Java 为主 + 自绘 Canvas 地图 | 1156 个 layout，地图自绘 |
| Aegis | Java + XML Views | 263 个 Java 文件 |
| Termux | Java + XML Views | 终端模拟器 + NDK |
| Syncthing-Android | Java + XML Views | 官方壳，核心 Go |
| KeePassDX | Kotlin + XML Views | 90 个 layout |
| MaterialFiles | Kotlin + ViewBinding | 58 个 layout |
| ownCloud | Kotlin + XML Views | 102 个 layout |
| Wikipedia | Kotlin + XML Views | 249 个 layout，Compose 迁移早期 |
| Nextcloud | Kotlin + XML Views | 189 个 layout，部分模块 Compose |
| Element（旧版） | Kotlin + XML Views | 490 个 layout，已被 Element X 取代 |

### 3.3 跨平台

| 应用 | 框架 | 数据 |
| --- | --- | --- |
| Immich | Flutter | 846 个 Dart 文件 |
| Ente Photos | Flutter | 1991 个 Dart 文件 |
| Aves | Flutter | 904 个 Dart 文件，插件化 |
| Joplin | React Native + TypeScript | 少量原生 Java 壳 |
| Logseq | React Native | Android 壳 + RN |
| Standard Notes | React Native | 同上 |

### 3.4 C++/NDK 重客户端

- Organic Maps：C++ 核心（1529 个 cpp）+ Java 壳（231 个 layout），地图自绘。
- VLC、Telegram：NDK 重度使用。
- OsmAnd：Java + 自绘地图。

### 3.5 规律

- 2018 年前的项目基本是 Java + XML Views；2019–2022 转向 Kotlin + Views；2023 年后新项目默认 Compose。
- Compose 渗透是渐进的，Signal、Wikipedia、Nextcloud、Firefox 都是 Compose 与 XML 长期共存。
- KMP 正在起势：F-Droid、Thunderbird、Bitwarden、Florisboard、NewPipe 的 shared 模块都在迁移。
- 性能敏感或历史包袱重的应用不跟风：Telegram、VLC、OsmAnd、Organic Maps 保持自绘/C++。

## 4. 框架原理

### 4.1 Jetpack Compose

- Android 专用声明式 UI 框架，Kotlin 函数描述界面，状态变化触发重组。
- 只支持 Android；跨端版本是 JetBrains 的 Compose Multiplatform。

### 4.2 Flutter

- Dart 写代码，自带渲染引擎（Impeller，旧版 Skia）自绘 UI，系统只提供画布。
- 渲染链路：Widget → Element → RenderObject → Layer → Engine → GPU。
- 与原生通过 Platform Channel 通信；需要嵌入原生控件时用 PlatformView。
- 优点：UI 像素级一致、动画和滚动可控；代价：引擎随包分发、体积大、深度系统集成较绕。

### 4.3 React Native

- JS/TS + React 描述界面，最终创建和更新系统原生控件。
- 新架构（0.76 起默认）：JSI（C++ 直接绑定）、Fabric（C++ Shadow Tree）、TurboModules、Codegen、Hermes。
- 布局用 Yoga（Flexbox），渲染交给平台 View 系统。
- 优点：观感原生、包体较小、原生能力接入直接；代价：JS/原生边界、跨线程通信、复杂动画需优化。

### 4.4 Compose Multiplatform 与 KMP

- KMP：共享业务逻辑，UI 各平台原生（Android Compose、iOS SwiftUI）。
- Compose Multiplatform：在 KMP 基础上共享 UI，支持 Android、iOS、桌面、Web(Wasm)，官方不支持鸿蒙。

### 4.5 对比

| 维度 | Jetpack Compose | Flutter | React Native |
| --- | --- | --- | --- |
| UI 由谁绘制 | Android 原生 | Flutter 引擎自绘 | 系统原生控件 |
| 语言 | Kotlin | Dart | JS/TS |
| 跨端 | 仅 Android | Android/iOS/桌面/Web | Android/iOS（桌面靠社区） |
| UI 一致性 | — | 像素级一致 | 接近原生，有平台差异 |
| 包体积 | 小 | 较大 | 较小 |
| 主要瓶颈 | — | GPU 光栅化、PlatformView | JS 线程、列表复用 |
| 鸿蒙 | 不支持 | 社区 fork | RNOH 生态较全 |

## 5. 多端能力矩阵

| 方案 | Android | iOS | 鸿蒙 NEXT | 桌面 | Web | 小程序 |
| --- | --- | --- | --- | --- | --- | --- |
| 原生 | ✅ | ✅ | ✅（ArkTS） | ❌ | ❌ | ❌ |
| Flutter | ✅ | ✅ | ⚠️ 社区 fork | ✅ | ✅ | ❌ |
| React Native | ✅ | ✅ | ⚠️ RNOH | ⚠️ 社区 | ⚠️ | ❌ |
| Compose Multiplatform | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ |
| KMP（仅逻辑） | ✅ | ✅ | ❌ 官方 | ✅ | ✅ | ❌ |
| Kuikly | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| uni-app | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ |
| Tauri Mobile | ✅ | ✅ | ❌ | ✅ | — | ❌ |

说明：⚠️ 表示依赖社区或厂商适配，成熟度和长期维护需单独评估。

## 6. 移动端本地后端（Go/Rust）

### 6.1 三种形态

| 形态 | 说明 | Android | iOS |
| --- | --- | --- | --- |
| 远程后端 | 手机作为客户端连接服务器 | ✅ | ✅ |
| 进程内 native 库 | Go/Rust 编译成 `.so`/`.a`，通过 FFI/JNI 调用 | ✅ | ✅ |
| 本地服务进程 | App 内起 HTTP/WebSocket 服务 | ✅ | ⚠️ 后台受限 |

### 6.2 接入方式

| UI 框架 | Go | Rust |
| --- | --- | --- |
| Flutter | 插件包 AAR/XCFramework，或 c-archive + `dart:ffi` | `flutter_rust_bridge` 或 `dart:ffi` |
| React Native | gomobile AAR/XCFramework + TurboModule | uniffi + TurboModule，或 JSI |
| Kotlin/Compose | JNI / AAR | JNI |
| SwiftUI | XCFramework / C ABI | XCFramework / C ABI |

### 6.3 限制

- iOS 不能动态加载库，Go/Rust 必须静态链接或打成 XCFramework。
- Go 的 `gomobile` 官方标注 experimental，复杂类型/回调支持有限，包体积和 GC 开销明显。
- Rust 需要处理 panic 跨 FFI、JNI 线程附着、交叉编译和体积控制。
- 本地服务在 iOS 后台会被挂起，不能作为常驻方案。
- 上架合规：native 库随包分发可以，动态下发可执行代码不行。

### 6.4 对本项目的判断

第一阶段不建议把 AI 推理或语音处理放进手机本地：模型调用和密钥应在服务端，客户端只负责采集、播放和交互。等出现明确的离线/隐私/成本需求，再评估 Rust 本地核心。

## 7. 市场格局

### 7.1 全球：Flutter 与 RN 双寡头

| 框架 | GitHub Stars（2026-11-11） | npm 周下载 | 背后 |
| --- | ---: | ---: | --- |
| Flutter | 181k | —（Dart 生态） | Google |
| React Native | 127k | 2094 万 | Meta |
| Expo | 53k | 1669 万 | Expo |
| Ionic | 53k | Capacitor 773 万 | Ionic |
| .NET MAUI | 23k | — | 微软 |
| Compose Multiplatform | 19k | — | JetBrains |
| Lynx | 15k | 1.8 万 | 字节 |
| Kuikly | 3.6k | — | 腾讯 |

- Flutter 官方 Showcase 覆盖 Google Pay、Google Classroom、Toyota、BMW、Alibaba（闲鱼）、ByteDance、Tencent、SoFi、Nubank、Wolt、Xiaomi、LG、Supercell 等。
- React Native 官方 Showcase 覆盖 Meta（Facebook、Instagram、Ads Manager）、Microsoft（Office、Outlook、Teams、Xbox）、Amazon（Shopping、Alexa、Photos、Kindle）、Shopify（全部移动端）、Wix。

### 7.2 中国：Flutter、RN、uni-app/Taro 三分，鸿蒙是新增变量

| 场景 | 主流选择 |
| --- | --- |
| App 跨端（电商、工具、出海） | Flutter 领先 |
| 社交/内容/大厂存量 | React Native、自研框架 |
| 小程序 + App + H5 多端 | uni-app、Taro 主导 |
| 鸿蒙原生 | ArkTS + ArkUI |
| 鸿蒙跨端适配 | RNOH、Kuikly、uni-app、Flutter 社区 fork |
| 政企/内部工具 | uni-app、Ionic、原生 |

### 7.3 趋势

- 从“UI 全共享”转向“逻辑共享 + 原生 UI”，KMP 增长。
- 鸿蒙成为新的适配市场。
- 动态化/热更新仍是国内刚需，RN、Kuikly、Lynx 更适配。
- 原生声明式 UI（Compose/SwiftUI）提升原生开发效率，纯 UI 跨端优势缩小。
- 大厂自研框架外溢（Kuikly、Lynx），市场从双寡头变为“双寡头 + 区域玩家”。

## 8. 针对本项目的选型分析

### 8.1 项目技术特征

- 第一阶段：手机文字聊天骨架、角色与对话记录可恢复、形象/声音能力分别验证。
- 交互密集：聊天列表、流式输出、录音、播放、角色切换、表情状态。
- 形象展示：可能涉及图片、序列帧、Live2D/骨骼动画，性能要求待验证。
- 语音：TTS/ASR 可能用云服务，客户端负责采集、播放、取消和状态同步。
- 数据：角色、会话、消息、资源绑定，需要本地持久化和恢复。
- 多端：Android/iOS 优先，鸿蒙是未来可能项；桌面暂无强需求。
- 团队：四条工作线，成员技术背景尚未定案。

### 8.2 候选方案评分

评分 1–5，5 为最优，仅用于相对比较。

| 维度 | Flutter | RN + Expo | KMP + CMP | 原生双端 |
| --- | ---: | ---: | ---: | ---: |
| 开发效率（双端一套） | 5 | 4 | 3 | 2 |
| UI 一致性 | 5 | 3 | 4 | 1 |
| 动画/渲染可控性 | 4 | 3 | 4 | 5 |
| 包体积 | 2 | 3 | 4 | 5 |
| 生态与第三方库 | 4 | 5 | 2 | 5 |
| 鸿蒙可行性 | 2 | 3 | 1 | 4（ArkTS） |
| 团队学习成本 | 3 | 3（有 React 基础则 5） | 2 | 2 |
| 长期维护稳定性 | 4 | 3 | 3 | 5 |

### 8.3 推荐

**首选：Flutter**

- 一套 UI 覆盖 Android/iOS，聊天、语音、形象组件只需维护一套交互。
- 自绘引擎让动画、滚动、表情切换更可控，适合陪伴类产品的表现力需求。
- 官方库整齐，版本行为一致，小团队少踩坑。
- 主要代价是包体积和深度系统集成；本项目第一阶段不依赖后者。

**备选：React Native + Expo**

- 团队若有 React/TypeScript 基础，上手最快，生态最大。
- 包体积比 Flutter 小，原生模块接入直接。
- 鸿蒙有 RNOH 路径，比 Flutter 社区 fork 更明确。
- 代价是复杂动画、长列表、音频状态同步需要更多调优。

**暂不推荐：KMP + Compose Multiplatform**

- 体积和性能接近原生，Android 团队迁移成本低。
- 但生态小、学习成本高，第一阶段团队还未稳定，容易把时间花在工具链上。

**原生双端**

- 形象渲染或音频延迟成为硬瓶颈时的兜底方案。
- 成本最高，第一阶段不建议。

### 8.4 建议的分阶段路线

**阶段一：文字聊天骨架**

- Flutter（或 RN）+ REST/SSE 接对话服务。
- 本地 SQLite 保存角色、会话、消息；启动时恢复。
- 云端 TTS/ASR，客户端只做录音、播放、取消。
- 形象先用图片/序列帧/简单动画，验证组件接口和性能。
- 建立统一请求标识、取消、失败回退等共同约定。

**阶段二：语音联动与形象增强**

- 完整语音链路：录音 → ASR 草稿 → 确认发送 → TTS 播放。
- 评估 Live2D/骨骼动画方案，确认帧率、内存、包体积。
- 推送与后台策略：iOS 走 APNs，Android 接厂商通道。
- 补离线缓存、弱网重试、角色切换时的音频停止。

**阶段三：多端与鸿蒙评估**

- 根据真实需求决定是否做鸿蒙；优先评估 RNOH、Kuikly、ArkTS。
- 若业务核心稳定，评估把协议/调度抽成 Rust 或 KMP 共享层。

### 8.5 关键风险与验证项

| 风险 | 影响 | 验证方式 |
| --- | --- | --- |
| Live2D/骨骼动画在跨端框架中的性能 | 帧率、内存、体验 | 真机 PoC，测帧率/内存/包体积 |
| 音频采集与播放延迟、回声 | 语音交流体验 | 真机录音→ASR→TTS 全链路测试 |
| 流式响应与取消 | 消息错乱、重复保存 | 模拟弱网、取消、切换角色 |
| 后台与推送 | 消息触达 | iOS/Android 真机推送与后台恢复 |
| 包体积 | 下载转化 | release 包按 ABI 拆分实测 |
| 鸿蒙适配 | 未来市场覆盖 | 单独 spike，不阻塞阶段一 |
| 团队技能匹配 | 开发效率 | 先做 1–2 周技术验证再定案 |

## 9. 建议的 PoC 清单

1. 聊天列表 + 流式输出 + 取消 + 弱网重试。
2. 录音 → ASR 草稿 → 用户确认发送。
3. TTS 播放、切换角色停止旧音频、失败保留文字。
4. 形象组件：图片/序列帧/Live2D 的帧率、内存、包体积对比。
5. 本地 SQLite 保存与恢复角色、会话、消息。
6. iOS/Android 推送与后台恢复。
7. release 包体积、冷启动耗时、长时间聊天内存曲线。

## 10. 数据来源与说明

- GitHub 仓库默认分支的构建文件与源码统计，查询日期 2026-11-11。
- Flutter Showcase：https://flutter.dev/showcase
- React Native Showcase：https://reactnative.dev/showcase
- GitHub Stars 与 npm 周下载量为 2026-11-11 实时查询。
- 市场判断基于公开资料与上述指标，未引用单一付费报告的具体百分比；不同调查口径差异较大，选型应以本项目 PoC 为准。