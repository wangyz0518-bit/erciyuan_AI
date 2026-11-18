# erciyuan_AI 长期开发最终执行计划（现有 PR 复用优先）

> 日期：2026-11-18
> 状态：2026-11-18 技术路线快照；完成情况以 Issue/PR 为准
> 仓库：[wangyz0518-bit/erciyuan_AI](https://github.com/wangyz0518-bit/erciyuan_AI)
> 当时任务盘点：#34～#44、#47 等任务及其依赖；历史数量不代表当前状态
> 本计划原则：**先审查已有 PR 的实际代码，尽可能移植已有稳定实现，才补新功能；避免原样合并历史叠加 PR**。
> 本文件只记录技术范围、复用和验收参考，不设置个人审批或执行模式。

## 1. 目标、不变量和范围

**最终目标**：基于 Flutter + Dart 的 Android/iOS 人物中心 AI 陪伴 MVP：每个人物只有**一条持续存在的逻辑时间线**，可恢复原始历史，三层记忆可检索/追溯，真实 AI 文字回复能使用人物身份与记忆；随后补齐正式 UI、平台验证、音频、ASR/TTS、人物形象。

已确定不可逆转的产品约束：

1. **人物是状态主体**，不能把多模型请求、摘要批次、归档窗口或语音连接暴露为“新建会话/切换会话”。按 owner_id + character_id 隔离一切读写、检索、缓存和导出。
2. 三层数据：RawEvent 原始事实（不因归档删除）；ArchiveSegment/MemorySummary 索引（保留原始事件引用）；PersonaIdentityVersion 人物身份（用户明确设定和动态归纳分开，改动可审计）。
3. 完整、版本化、供应商无关的可携带导出。#36 先完成原始数据导出，#47 扩展三层与来源；可纠错/删除与下游摘要失效同步。
4. “长期连续上下文”是产品体验目标，并不意味着单次模型无限 Token。稳定人物身份前缀置前；相关记忆及近期原文按需装配；实际缓存命中率、成本和质量须 #39 真实测量。
5. **接受 ADR-0004 方案 2**：保留 apps/mobile_poc/ 原样作为验证工程；另建 apps/mobile/ 为正式工程；逐步落实 app → application → domain/ports 与可替换适配器，构造函数注入，不提前引入无调用方框架。
6. 核心范围不含未创建 Issue 的账号/云同步/鸿蒙/正式商店发布；生产上线与额外收费也不因本计划自动授权。

关键架构文档：[ADR-0004](../docs/decisions/0004-person-centered-memory-architecture.md)、[总体架构](../docs/design/flutter-memory-first-architecture-20261118.md)、[人物记忆数据契约](../docs/design/person-memory-data-contract-20261118.md)、[人物中心原则](../docs/design/person-centered-companion-principles-20261118.md)。

## 2. 如何复用未合并的已有 PR

### 2.1 复用与移植方式

- PR #15～#24 包含既有设计与实现，按实际增量和当前 main 的兼容性选择复用方式。
- 一些 PR 继承了尚未合并的其他 PR：例如 #21 基于 #16，#22 基于 #21，#24 基于 #22。**PR Changed Files 并不是该 PR 独立开发量**，不得直接整分支 merge 或不加区分地 cherry-pick 大量历史提交。
- 每项先定位源 PR 的**增量提交/文件**、相对父级实际差异和与最新 main 的差异；建立“复用表”：源 PR+commit+path，复用方式（直接移植/适配/只参考/弃用），原因，接口/测试差异和许可。
- 通过明确的文件级移植或精确补丁复用；保留来源/贡献说明和适用许可证，移除实验密钥/本机路径/真实私人数据/未授权 SDK 与素材。相同文件若已进入 main，直接使用 main 版本，不能反向覆盖。
- 先跑源模块在可用环境中的基线测试，移植后增加正式人物作用域、安全/接口/平台测试；不能因 PoC 跑通就判定正式 Android+iOS、生产鉴权或真实长记忆已通过。
- 避免重新设计已被认可的首页、聊天交互、DeepSeek/流式网关、音频和 Live2D 核心。**必须新设计/实现的**主要是人物中心复合数据边界、长期记忆内核、用户数据全量可追溯导出以及生产安全/双端适配。

### 2.2 已核对的源 PR 与代码入口

| 源 PR（所有者 wangyz0518-bit） | 可复用文件或成果 | 目标 Issue | 约束 |
| --- | --- | --- | --- |
| [#15 沉浸聊天原型](https://github.com/wangyz0518-bit/erciyuan_AI/pull/15) | 设计/交互参考 | #37 | A 人物主页优先，B 最近人物恢复作对照；不移植多会话体验 |
| [#16 Flutter 聊天](https://github.com/wangyz0518-bit/erciyuan_AI/pull/16) | apps/mobile_poc/lib/immersive_chat_page.dart；lib/widgets/chat_composer.dart、chat_messages.dart、chat_sidebar.dart、character_scene.dart；lib/audio_controller.dart；integration_test/immersive_test.dart 与角色/取消回归 | #35 最小测试思路、#37 UI、#42 音频 | 选择性移植组件，状态和读取必须接正式 owner+character/RawEvent；不复制整套老工程 |
| [#17 Live2D 插件](https://github.com/wangyz0518-bit/erciyuan_AI/pull/17) | packages/live2d_avatar/；lib/avatar_package_page.dart；integration_test/avatar_package_test.dart、live2d_regression_test.dart；ZIP 契约/错误包 | #44 | Android 原型可复用但 iOS 实现、SDK 许可、模型分发、真机/能耗未验收 |
| [#18/#19 端侧与云语音研究](https://github.com/wangyz0518-bit/erciyuan_AI/pull/19) | experiments/voice_poc/ 的对比脚本/测试和报告；#18 技术方案 | #43 | 作为候选/评估证据；不把个别听感或数字视为最终供应商结论 |
| [#20 Cubism 人物素材](https://github.com/wangyz0518-bit/erciyuan_AI/pull/20) | planning/demos/dragon-layers/ 的 CMO3/MOC3、纹理及 idle.motion3.json、制作脚本和报告 | #44 | 许可/素材归属核实后复用；基本翼尾动作不代表完整成品角色 |
| [#21 DeepSeek + CosyVoice 网关](https://github.com/wangyz0518-bit/erciyuan_AI/pull/21) | services/model_gateway/gateway/app.py、providers.py、tests/test_gateway.py；apps/mobile_poc/lib/model_gateway.dart、reply_speech_controller.dart；v0 契约 | #38、#39、#43 | 复用 provider、SSE 与取消/重试逻辑；重做服务端鉴权、隔离/权限和正式记忆接口；ASR 仍是未实现占位 |
| [#22 流式语音](https://github.com/wangyz0518-bit/erciyuan_AI/pull/22) | gateway/streaming.py、speech_pool.py、tests/test_streaming.py；apps/mobile_poc/lib/streaming_gateway.dart、pcm_player.dart；Android PcmPlayer.kt；v2 契约 | #38、#39、#42、#43 | Android PCM 已验证，iOS PCM 不存在；需校验协议安全/弱网/并发、依赖旧网关的部分 |
| [#23 文字音色微调实验](https://github.com/wangyz0518-bit/erciyuan_AI/pull/23) | 失败/负面研究结论与实验测试 | #43 | 当前暂停，不默认重启实验或复制失败路线 |
| [#24 Windows 音色复刻](https://github.com/wangyz0518-bit/erciyuan_AI/pull/24) | services/model_gateway/gateway/voice_enrollment.py、voice_profiles.py、voice_store.py、tests/test_voice_profiles.py；apps/windows_voice_lab/；音色契约 | #38、#43 | 保留后台音色任务与绑定/幂等能力；补授权、租户隔离、删除语义、平台 UI；Windows 测试台不等于移动端功能 |
| main 的本地 PoC（已合并基线） | apps/mobile_poc/lib/data.dart、chat_controller.dart、integration_test/acceptance_test.dart、storage_failure_test.dart；现有 Flutter/Android CI | #35、#36、#47 | 在正式工程重建正确数据契约，不把 PoC schema 当成生产数据库或直接迁移本机测试数据 |

## 3. 11 项批量工作包（严格按依赖实施）

| 顺序 | Issue | 复用优先内容 | 本轮真正要完成的新增/适配 | 完成门槛 |
| --- | --- | --- | --- | --- |
| 1 | [#35 正式 Flutter 工程](https://github.com/wangyz0518-bit/erciyuan_AI/issues/35) | main 的 PoC Flutter 工具链/Android CI；#16 页面/测试结构思路 | 建 apps/mobile/ Android+iOS 模板、启动组合根、轻量状态/导航、人物 scope、内存 Mock A 主页和唯一聊天入口 | Flutter format/analyze/unit/widget、Android Debug APK CI 通过；两人物作用域不串；PoC 未破坏。不提前做 SQLite/模型/正式 UI |
| 2 | [#36 原始数据层](https://github.com/wangyz0518-bit/erciyuan_AI/issues/36) | main 的 data.dart、chat_controller.dart、SQLite 失败/重启回归；#16/#21/#22 的取消与角色切换案例 | 正式 Character/CharacterTimeline/RawEvent/GenerationTask、SQLite 复合 owner+character 键、事务/迁移/历史分页、可携带 JSON/JSONL 原始数据一键导出 | 新建/迁移/回滚/异常重启/取消重试/导出 round-trip/跨人物负向测试，不产生孤立事件或伪会话 |
| 3 | [#47 三层记忆内核](https://github.com/wangyz0518-bit/erciyuan_AI/issues/47) | #36 事实仓储；#21/#22 请求状态和过滤；#24 任务幂等/绑定经验 | 归档水位/幂等任务、确定性摘要器、摘要到 RawEvent 来源、人物隔离检索回查、固定/动态身份候选审核、稳定上下文装配、纠错与三层导出 | 摘要有来源、重跑不重复、异常可恢复、删除/修正失效下游摘要、不同人物完全隔离；Mock 不宣称真实 LLM 质量/缓存命中率 |
| 4 | [#38 AI/后端设计](https://github.com/wangyz0518-bit/erciyuan_AI/issues/38) | 审阅 #21/#22/#24 网关实际代码和 v0/v2/音色契约，沿用成熟协议/状态模型 | 基于现有网关做“保留/改造/淘汰”决策；多用户鉴权、最小化日志、配额/限流、密钥、request_id、provider 适配、部署与成本/隐私 ADR | 可追溯 API/威胁模型/安全矩阵、已有实现复用表；不把本机开发 token 视为生产鉴权；不提前公网部署 |
| 5 | [#39 真实文字 AI/记忆联调](https://github.com/wangyz0518-bit/erciyuan_AI/issues/39) | #21 gateway app/providers 和 Flutter 网关客户端；#22 streaming 通用机制 | 适配 #47 记忆装配、按人物上下文/服务权限、流式文本、取消/重试/幂等/中断、SQLite 最终消息和可替换 Mock | 后端+客户端自动化回归；若有授权凭据则真实 LLM 端到端测 Token/召回/Prompt Cache/延迟/费用。无真实凭据时不标“真实联调已完成” |
| 6 | [#37 人物中心正式 UI](https://github.com/wangyz0518-bit/erciyuan_AI/issues/37) | #15 交互、#16 Flutter 页面和 UI/键盘回归；#14 已确认 A/B 原型 | A 人物主页优先为正式主路径、B 最近人物恢复为对照；正式人物/消息 Repository、状态/历史/导出入口；连接 #39 文本适配 | 首次/回访/切人物、375px/字体/键盘/安全区/返回/无障碍测试；不得出现新建会话或混入另一人物历史 |
| 7 | [#40 iOS 模拟器](https://github.com/wangyz0518-bit/erciyuan_AI/issues/40) | main 的 iOS 模板、#16 插件参考 | macOS/Xcode Flutter iOS Simulator 构建、启动、插件配置与 CI | 必须真实 macOS runner 或 Xcode 证据；无环境记录阻塞；不把存在 ios/ 目录视为 iOS 通过 |
| 8 | [#41 Android 真机](https://github.com/wangyz0518-bit/erciyuan_AI/issues/41) | #16 Android 模拟器测试步骤、main 的 SQLite 回归 | 在真实 Android 设备安装正式 App，验证启动/导航/中文输入/权限/后台/重启及人物隔离 | 设备/OS/build/log 及可复现记录；无真机则标阻塞，不能用模拟器冒充 |
| 9 | [#42 正式音频底座](https://github.com/wangyz0518-bit/erciyuan_AI/issues/42) | #16 audio_controller.dart、hold_to_record_test；#21 文件音频；#22 Android pcm_player.dart/PcmPlayer.kt | 录音/播放端口、系统权限、临时文件清理、生命周期、音频乱序/迟到失效；iOS 支持策略 | 自动化权限/取消/切人物/后台/释放测试；Android/iOS 能力与设备试听单独记录；不等于 ASR |
| 10 | [#43 ASR/TTS 及音色](https://github.com/wangyz0518-bit/erciyuan_AI/issues/43) | #18/#19 供应商筛选；#21 TTS WAV；#22 流式 PCM；#24 音色服务与 Windows 测试台；#23 负面结论 | **ASR 是主要新增功能**：录音识别→可编辑→用户确认→发送；TTS/音色绑定与取消/重试/授权/云端删除；Android/iOS 差异适配 | 未确认识别结果不得发送；角色/用户不串音色；文字始终可用；真实听感、服务调用、权限与删除证据齐备才验收对应能力 |
| 11 | [#44 Live2D 与人物资源](https://github.com/wangyz0518-bit/erciyuan_AI/issues/44) | #17 packages/live2d_avatar 插件/ZIP 校验/动作+异常测试；#20 有条件复用 Cubism 源模型和动作 | 接入正式人物 UI、静态降级、资源版本/校验/安全导入、idle/talking 等状态/销毁管理，明确 iOS 策略 | 合法 SDK/模型授权、实际 Android 设备渲染与回归、坏包拒绝与稳定降级；未满足许可/平台条件不得宣称正式 Live2D 全端通过 |

**执行顺序**：#35 → #36 → #47 → #38 → #39 → #37 → #40 → #41 → #42 → #43 → #44。

这是优先级顺序，**不是全部的硬依赖链**。硬依赖：#35→#36→#47→#38→#39；#37 至少依赖 #35/#36，后排是为了实际对接 AI；#40 依赖 #35；#41 依赖 #35/#36/#37；#42 依赖 #35、与数据/UI 接口对齐；#43 依赖 #38/#39/#42；#44 依赖 #35/#37、SDK/素材许可。若 #39 因凭据阻塞，可先完成 #37 与 Mock UI，再回来联调，不以等待外部服务阻塞全部可独立任务。

## 4. #31 暂缓事项

[#31 Android 模拟器集成 CI](https://github.com/wangyz0518-bit/erciyuan_AI/issues/31) 仍为第 12 个未完成 Issue，继续暂缓，现有 [PR #32](https://github.com/wangyz0518-bit/erciyuan_AI/pull/32) 与 [PR #49](https://github.com/wangyz0518-bit/erciyuan_AI/pull/49) 的状态以 GitHub 为准。#35 的独立快速 Flutter/Android Debug CI **并不等于** #31 的模拟器集成验收。恢复时间可由团队按进展协调；其他产品方向不自动纳入本路线。

## 5. 技术实施与验证参考

- 按技术依赖选择任务，参考已有 Issue、设计与可复用实现。
- 根据实际改动运行必要测试；区分真实、模拟、失败及未验证。
- 涉及公共接口、数据或平台的变更，注意同步实现与文档。
- 任务状态及验收证据以 GitHub Issue/PR 为准。

## 6. 外部资源与安全边界

列入技术路线不代表外部资源、许可或部署条件已具备：

- **真实 AI 与费用**：DeepSeek/其他付费供应商的真实密钥、账号、额度上限、隐私告知、生产服务与外发数据。可写代码/Mock；使用付费 API、上传用户数据或公网部署前应确认必要授权与安全措施。
- **iOS**：macOS/Xcode 环境与 GitHub macOS runner 的实际可用性；无设备/环境时记录缺口，不宣称 iOS 真正构建完成。
- **Android 真机**：需实机与调试授权；不能凭模拟器报告关闭 #41。
- **ASR/TTS/音色**：真实服务密钥、真实录音/音色采集授权、删除/保留要求与人工试听；不能用模拟 WAV 冒充真实语音质量。
- **Live2D**：Cubism SDK/Core 授权、角色模型版权/许可、Android/iOS 适配与实际设备；不能把未经许可的二进制或素材提交到仓库。
- **架构范围变动**：任何推翻 ADR-0004 的决定、新增原定范围外账号云同步/支付/云部署等核心产品需求，需要相关参与者讨论确认。
- **技术/组织阻塞**：CI 未通过、必要审阅尚未完成、他人代码版权许可不明、必要设备缺失时，保留 open 的 PR/Issue；允许转做无依赖工作并在最终报告标注。

## 7. 最终交付的质量分层

最终不要只报一个“11/11 完成”，而应逐项标识：

- **代码与离线验证完成**：源码、契约、测试、构建/CI 可复现。
- **真实联调完成**：有真实模型/语音/硬件与样本日志；与 Mock 分开。
- **双平台完成**：Android 与 iOS 各有对应的构建、安装或运行证据；iOS 模板不是 iOS 运行。
- **生产就绪**：需要单独的鉴权、许可证、安全、部署、监控和发布决策，默认本批不作承诺。

最终验收文件建议为 plan/batch-delivery-report-20261118.md（在实际收尾时创建，记录后续真实日期），包含：每项 Issue/PR/merge commit/status、源码复用追踪、测试命令与 CI 链接、平台/模型真实证据、已知问题和剩余权限/成本/安全决策。

## 8. 历史计划说明

这是 2026-11-18 的技术路线快照，不规定任何成员的 PR 操作权限、审批方式或 AI 执行节奏。实际状态以当前 GitHub Issue/PR 和验证记录为准。
