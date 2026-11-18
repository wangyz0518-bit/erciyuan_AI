# erciyuan_AI 长期开发最终执行计划（现有 PR 复用优先）

> 日期：2026-11-18
> 状态：**等待用户一次性确认本最终计划**；ADR-0004 方案 2、#35 详细计划已经单独批准；未开始正式工程实施
> 仓库：[wangyz0518-bit/erciyuan_AI](https://github.com/wangyz0518-bit/erciyuan_AI)
> GitHub 盘点：6 个已关闭 Issue（#7、#8、#10、#14、#25、#34）；12 个仍开放 Issue；建议本轮完成 11 项，#31 继续暂缓
> 本计划原则：**先审查已有 PR 的实际代码，尽可能移植已有稳定实现，才补新功能；避免原样合并历史叠加 PR**。
> 总审批后：11 项按依赖逐项开发、独立 PR、自审/CI、合并并记录；不再要求逐项确认普通执行计划，最终集中给出验收报告。遇到特殊外部授权/质量门槛需停止受影响部分。

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

### 2.1 权限与移植方式

- 执行账号是 **keeyangyy**；只修改、审核、合并或关闭 **keeyangyy 创建的 PR**。仓库所有者 **wangyz0518-bit** 的 PR #15～#24 均仅允许阅读及参考，**不得修改 PR、向其分支提交、合并或关闭**。Issue 可处理所有作者的。
- 一些 PR 继承了尚未合并的其他 PR：例如 #21 基于 #16，#22 基于 #21，#24 基于 #22。**PR Changed Files 并不是该 PR 独立开发量**，不得直接整分支 merge 或不加区分地 cherry-pick 大量历史提交。
- 每项先定位源 PR 的**增量提交/文件**、相对父级实际差异和与最新 main 的差异；建立“复用表”：源 PR+commit+path，复用方式（直接移植/适配/只参考/弃用），原因，接口/测试差异和许可。
- 通过本人新分支的明确文件级移植或精确补丁复用；保留来源/贡献说明和适用许可证，移除实验密钥/本机路径/真实私人数据/未授权 SDK 与素材。相同文件若已进入 main，直接使用 main 版本，不能反向覆盖。
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

[#31 Android 模拟器集成 CI](https://github.com/wangyz0518-bit/erciyuan_AI/issues/31) 仍为第 12 个未完成 Issue，继续暂缓，现有 [PR #32](https://github.com/wangyz0518-bit/erciyuan_AI/pull/32) 与 [PR #49](https://github.com/wangyz0518-bit/erciyuan_AI/pull/49) 不动。#35 的独立快速 Flutter/Android Debug CI **并不等于** #31 的模拟器集成验收。解除暂缓需要独立授权；其他产品方向（账号、云同步、鸿蒙、商店发布）本轮不自动增加。

## 5. 执行 SOP（批量批准之后每项自动套用）

1. **检查**：读取当前 main HEAD、该 Issue、现有设计、相关 PR 的实际增量路径与提交。检查外部 PR 是否被原作者更新或合并，始终以最新 main 为基准。
2. **任务局部计划**：在该 Issue 对应的 plan/ 记录精确复用来源、具体文件、变更清单、依赖、测试和退出标准；只有偏离已批准总范围或新的外部授权才再请求确认。
3. **本人独立分支开发**：以最新 main 起独立分支。优先保留/移植现有实现，补正式领域适配；不从他人未合并的大 PR 整体合入旧历史。PoC 应维持稳定。
4. **测试**：格式/静态分析/单元/Widget/集成/构建按适用能力执行；加跨人物、数据损坏、失败/重试、真实来源引用、权限/资源释放等负向测试。确实不具备的平台环境标明未验证，不用 Mock 代替。
5. **PR 与自审**：只提交 keeyangyy 的 PR，描述已有成果复用、被移植文件/来源 commit、是否变更接口/数据、实际执行的测试及结果、CI 链接、许可/隐私检查、遗留项。不假装作者可对自己的 PR 进行有效 GitHub APPROVE。
6. **合并门槛**：检查分支保护、必需 CI、冲突与所需 Review；未满足绝不绕过。仅可合并本人的 PR；若无权合并或要求独立审批，则保留 PR 阻塞，不能声称已合并。
7. **Issue 状态**：只有其承诺的功能、文档及必要验收已完成才关闭 Issue；如只有部分实现或缺真实设备/模型/授权则保持 open、记录已完成/阻塞/待验收。允许推进没有硬依赖的后续项，不伪造完成。
8. **最终集中复核**：整理 11 项完成状态、本人 PR URL 与 merge SHA、关键测试日志、Android/iOS/真实 AI/ASR/TTS/Live2D 的实际验证边界、复用来源、剩余阻塞和建议。用户最后一次查看整个结果。

每项 Issue **单独独立 PR**，不得以“整批开发”跳过逐项测试与可审计合并；总计划授权后无需每项结束再停下申请普通任务许可。每次进入下一个 Issue 时，从已更新 main 继续，不能预先把多个 Issue 的提交混在一个未合并分支。

## 6. 需要保留独立授权的风险

批量批准并不包括下列事项的自动授权：

- **真实 AI 与费用**：DeepSeek/其他付费供应商的真实密钥、账号、额度上限、隐私告知、生产服务与外发数据。可写代码/Mock；未经批准不得自作主张消费付费 API、上传用户数据或公开部署本机网关。
- **iOS**：macOS/Xcode 环境与 GitHub macOS runner 的实际可用性；无设备/环境时记录缺口，不宣称 iOS 真正构建完成。
- **Android 真机**：需实机与调试授权；不能凭模拟器报告关闭 #41。
- **ASR/TTS/音色**：真实服务密钥、真实录音/音色采集授权、删除/保留要求与人工试听；不能用模拟 WAV 冒充真实语音质量。
- **Live2D**：Cubism SDK/Core 授权、角色模型版权/许可、Android/iOS 适配与实际设备；不能把未经许可的二进制或素材提交到仓库。
- **架构范围变动**：任何推翻 ADR-0004 的决定、新增原定范围外账号云同步/支付/云部署等核心产品需求，必须另行批准。
- **技术/组织阻塞**：CI 未通过、分支保护不允许自审合并、他人代码版权许可不明、必要设备缺失时，保留 open 的 PR/Issue；允许转做无依赖工作并在最终报告标注。

## 7. 最终交付的质量分层

最终不要只报一个“11/11 完成”，而应逐项标识：

- **代码与离线验证完成**：源码、契约、测试、构建/CI 可复现。
- **真实联调完成**：有真实模型/语音/硬件与样本日志；与 Mock 分开。
- **双平台完成**：Android 与 iOS 各有对应的构建、安装或运行证据；iOS 模板不是 iOS 运行。
- **生产就绪**：需要单独的鉴权、许可证、安全、部署、监控和发布决策，默认本批不作承诺。

最终验收文件建议为 plan/batch-delivery-report-20261118.md（在实际收尾时创建，记录后续真实日期），包含：每项 Issue/PR/merge commit/status、源码复用追踪、测试命令与 CI 链接、平台/模型真实证据、已知问题和剩余权限/成本/安全决策。

## 8. 本轮审批与执行约定

1. 用户**已经批准** ADR-0004 方案 2 与 #35；本文件不再重复申请该两项批准。
2. **等待用户对本最终计划的一次性确认**。确认后，先审核并在符合必要 CI/Review 情况下合并承载计划的本人 Draft PR #51，再从最新 main 开始 #35 → 后续 10 项，不再逐项要求普通计划确认。
3. #31 **默认继续暂缓**；只有明确要求纳入时才变更。
4. 对缺少的真实凭据、预算、设备、版权/SDK 许可或分支保护批准，保持真实未完成状态，不以自动测试替代。
5. 本计划是 GitHub 中可跨会话继续的事实依据。**ChatGPT 不保证在对话结束后后台自动编码或无限期自行推进**；实际执行以当前可用的交互/工作会话为限。若会话中断，可在新会话按已批准范围和 GitHub Issue/PR 现状继续，无需重新确认未变动的范围。
