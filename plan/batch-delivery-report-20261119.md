# erciyuan_AI 2026-11-19 批次交付与验收报告

> 状态：2026-11-19 可独立交付的代码与离线测试已并入 main，**真实资源/设备/许可未验收的六个 Issue 继续开放**；以各 PR、Issue 和 Actions 的实际记录为准。此文档只记录共同维护的技术实现、实际测试及未满足的验收条件，不增加任何人的 GitHub 审批或权限规则。
>
> 项目：Flutter Android/iOS 人物中心 AI 陪伴应用。每个人物维持唯一持续时间线，按 owner_id + character_id 隔离 SQLite、原始历史/归档/身份记忆与完整数据导出。

## 已完成基线

- #34、#35、#36、#47、#38：架构、正式 Flutter 工程、人物原始时间线/导出、三层离线记忆内核及 AI 网关设计。
- #37：正式人物首页与唯一聊天 UI、SQLite 和导出集成测试，PR #59，合并 commit 644e07a4beddcb3649d35783c8f4181dc5d803e1；Android 真模拟器和截图测试通过，iOS 不在其验收范围。
- #39：DeepSeek SSE Provider、对角色身份与记忆上下文的装配、模型取消/失败/重试、服务端请求状态与离线 Mock 已有实现。禁止把使用 httpx.MockTransport 的自动化测试记为真实供应商调用。

## 2026-11-19 新增交付

| Issue | 增量 PR | 已交付范围 | 当前可证实的验证 | 仍缺少 |
| --- | --- | --- | --- | --- |
| #39 | [#66](https://github.com/wangyz0518-bit/erciyuan_AI/pull/66)，已合并 `96ce8f3` | live 模式完整 gateway → DeepSeek adapter → SSE → SQLite ledger 的无外网模拟上游回归；含上下文/幂等/权限隔离与错误脱敏 | [Person gateway CI 44371860150](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44371860150) 和 [Flutter CI 44371860174](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44371860174) 均 success | 真实付费 LLM 请求、Token/缓存/成本/质量、可复现用户服务联调 |
| #40 | [#60](https://github.com/wangyz0518-bit/erciyuan_AI/pull/60) | macOS/Xcode 无签名 iOS Simulator 构建、安装、启动、截图与 Flutter integration_test 脚本已并入 main，commit ab507fc96a11d498927f1af1a29cbd9ddad2df6f | macOS26 [44344176615](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44344176615) 两次在步骤前取消；macOS15 [44367835338](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44367835338) 同样取消；Flutter/Android 检查可通过 | 实际 macOS runner/Xcode 成功，真 iPhone Simulator 安装截图与集成测试 |
| #41 | [#61](https://github.com/wangyz0518-bit/erciyuan_AI/pull/61) | 只允许真实物理 Android 设备的安装/启动/SQLite 回归验收脚本与人工检查清单，commit 6157da3f2a8a1b7dfe1d5d85446fea847f450fd0 | [Flutter CI 44345139528](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44345139528) success | 有 ADB 权限的 Android 手机、型号/OS 版本、启动/导航/中文输入/后台/权限真机证据 |
| #42 | [#63](https://github.com/wangyz0518-bit/erciyuan_AI/pull/63) | record/audioplayers 本地录音和文件试听、取消/删除/后台/人物切换清理、Android PCM 原生端口、正式聊天 UI，commit ebcbfc3f6a1ec4ede82daba776d256fd6614a2ce | [Flutter CI 44367511368](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44367511368) success；[Android 模拟器 44367511417](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44367511417) success | Android/iOS 设备真实录音试听、权限中断和 PCM 音质；iOS 流式 PCM 未实现 |
| #43 | [#64](https://github.com/wangyz0518-bit/erciyuan_AI/pull/64)，已合并 `220e8d1` | 可编辑设备端 ASR 候选，只有手动填入草稿再发送；系统 TTS 的用户主动朗读与逐条明确同意、迟到语音与人物隔离 | [Flutter 44371264151](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44371264151) 和 [Android 模拟器 44371264714](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44371264714) 均 success | 真正角色绑定音色、TTS 供应商/声音资源许可和删除，iOS/Android 真人听感、延迟/准确率 |
| #44 | [#65](https://github.com/wangyz0518-bit/erciyuan_AI/pull/65)，已合并 `0f14ca4` | v0.1 资源描述安全预检与明确非 Live2D 的 Flutter 动作语义静态形象降级；不引入未经授权 Core/素材 | [Flutter 44371255558](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44371255558) 和 [Android 模拟器 44371255744](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44371255744) 均 success | 真正 ZIP 完整安全导入器、授权的 Cubism Core/人物资源、Android 实机真实 Live2D 动作与 iOS 验收 |

### 主线合并与组合检查

本次代码、测试与 CI 工具一共 6 个已合并 PR：#60（iOS CI 工具）、#61（Android 真机验收脚本）、#63（正式音频层）、#64（设备端 ASR/系统朗读）、#65（静态形象/manifest 预检）、#66（live Provider 零网络端到端回归）。全部为独立审查后合入 main 的增量，未覆盖或直接合并历史 PoC。

- #64 与 #65 合并后，在 main 的正式人物聊天页面静态检查同时包含音频录制入口、语音确认弹窗、ASR/TTS 控制器以及 AvatarFallbackScene；**仍需以 main 合并后最新 Actions 作为完整构建回归结论**。
- 由于仓库新增了 iOS workflow，所有涉及 apps/mobile 的 PR 均会触发 macOS 队列；job 未运行不应视为代码测试通过或失败。
- PR #67 仅更新本批交付报告和 plan 索引，不含功能代码；此文档本身不构成任何未通过验收的替代证据。

## 质量与隐私边界

1. 已检查的 Flutter CI 含 pub get、format、analyze、Widget/单元测试、Debug APK、375px 截图；Android 模拟器 CI 安装 APK 并执行正式集成测试。通过一层不意味着其他层完成。
2. #39 所有新增模拟 provider 测试均为本机 MockTransport；没有真实 paid API 密钥，不消耗费用、不进行外部部署；生产认证/预算/数据授权仍需独立审查。
3. #42 临时音频仅本地录制与试听，不作为聊天消息、不自动上传、不自动 ASR；#43 用户必须编辑识别结果并主动发送，系统 TTS 可能联网时需要本条文字单独同意。
4. #44 静态 Flutter 形象不是 Live2D。描述预检不检查 ZIP、符号链接、二进制 MOC3 或授权。不能把历史 PoC 成功扩大为正式人物、多平台或分发许可成功。
5. 没有物理 Android/iPhone、真实 macOS runner、获授权的付费模型/供应商或明确获许可的 Cubism Core/模型包时，这些 Issue 应继续开放；不能使用假数据/静态文件使验收项被误关闭。

## 需要外部条件才能关闭的事项

- **#39**：经批准且额度受控的真实 LLM API 凭据、隐私与费用边界、成功的实际模型 SSE/记忆联调。
- **#40**：能实际完成构建步骤的 macOS/Xcode 与 iOS Simulator CI，需截图及集成测试通过。现有多次 job 在任务步骤之前被取消，不是 iOS 构建结果。
- **#41**：至少一台可连接的真实 Android 手机及所有核对记录。
- **#42**：真实 Android/iPhone 麦克风/播放/停止与系统中断验证，iOS 音频支持范围独立确认。
- **#43**：角色专属音色及用户授权/删除/供应商合规，双端真实 ASR/TTS 质量与停止/错误回归。
- **#44**：有可验证分发授权的 Cubism SDK/Core 与角色包、受保护导入器、正式 App 动作/生命周期和真机证据。

## 结果定义

“已提交代码”、“已合并 PR”、“自动化 CI 成功”、“Android 模拟器运行”、“iOS 模拟器运行”、“Android/iPhone 物理真机”、“真实付费模型”、“许可合规”分别记录。任何一项不能代替另一项。所有开放的验收条件继续由各 Issue 跟踪。

## 任务会话 6 追加核验（2026-11-19，原批次之上的后续记录）

> 以上章节保留任务会话 5 的历史状态快照。本节反映后来实际发生的 GitHub 合并、iOS 验收和仍未满足的条件，不覆盖旧证据。此时 main 基线为 `f1d3be69fa1904e03422160f5327d2cdfdfc3e01`。

### 新增主线交付及验证

| Issue | PR / main commit | 完成范围与证据 | 验收结论 |
| --- | --- | --- | --- |
| #42 | [#68](https://github.com/wangyz0518-bit/erciyuan_AI/pull/68)，`07eb9b8a3bda610f3ec02ffa3a112ec57c0b5dd2` | 60 秒上限及计时器取消、自动停止保留试听、重复结束幂等；[Flutter](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44374453211) 与 [Android 模拟器](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44374453167) 通过 | 尚未双端真机录音/回听 |
| #44 | [#71](https://github.com/wangyz0518-bit/erciyuan_AI/pull/71)，`9a73d01481beda1ede80f7d4c50e52489e786959` | 离线、只读 ZIP 包结构/文件数量/大小/路径/重复项/符号链接/CRC/JSON 重复键预检；[Flutter CI](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44472898047)、[Android 模拟器](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44472898136) 均成功 | 非 Flutter 包导入器或授权 Live2D |
| #39 | [#73](https://github.com/wangyz0518-bit/erciyuan_AI/pull/73)，`7ef98e7ffdeaf372970a85da89292f8a7fe1f367` | 修复模型请求在 ledger 已 claim 后、SSE 尚未迭代时取消仍可能启动 Provider 的竞态；[Gateway CI](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44474006378)、[Flutter CI](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44474006457) 通过 | 假 Provider 调用次数为零，未做真实付费调用 |
| #43 | [#72](https://github.com/wangyz0518-bit/erciyuan_AI/pull/72)，`be43bc7e7530712811c526b7a974d5fc61dbbfb8` | 设备 ASR 开始时立即清除被中断系统 TTS 的旧状态，测试迟到回调；[Flutter CI](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44473560920)、[Android 模拟器](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44473560904) 通过 | 非角色专属声音、无真机听感 |
| #40 | [#74](https://github.com/wangyz0518-bit/erciyuan_AI/pull/74)，`f1d3be69fa1904e03422160f5327d2cdfdfc3e01` | 将实际 iOS Simulator 成功记录写回 [#40 计划](issue-40-ios-simulator-verification-20261118.md) | **Issue #40 已关闭**，不代表 iPhone 签名/真机 |

**iOS 模拟器成功证据**：

- [main iOS run #44471228989](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44471228989) 在 `07eb9b8a` 上 **success**：Xcode/Flutter 构建 Runner.app、iPhone 16 Pro Simulator boot/install/launch/实际截图、`acceptance_test.dart` 与 `storage_failure_test.dart` 均输出 `All tests passed!`；截图/App artifact ID 14504846550。
- [main iOS run #44474070987](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44474070987) 在 `9a73d014` 上再次 **success**，实际日志亦确认两个集成套件分别 `All tests passed!`。这两条是可复查的正式 iOS 模拟器验收，不是此前的 runner cancelled 状态。
- 后续部分 macOS 作业虽能编译和运行第一项测试，仍可能在第二个 Flutter 集成测试启动时卡住并被作业超时取消；取消作业不视为第二项成功。排查与音频增量分别追踪。

**待合并/独立复测**：[#70](https://github.com/wangyz0518-bit/erciyuan_AI/pull/70) 属于 #42，选择性复用现有 PoC 的 Swift `ConversationPlayer`（仅 AVAudioEngine PCM16LE 24 kHz 输出，不复用受限制模型、ONNX 或云供应商代码），接到正式 iOS Runner 的 Flutter channel。其 [Flutter](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44472978741) 和 [Android 模拟器](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44472978755) 成功；首次 [iOS run](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44472978608) 显示 Xcode 编译/安装/截图/首个集成测试成功，但第二套件执行阶段超时取消，**不得认定 #70 全套 iOS CI 已成功**。已发起重跑，合并前再次核验最新提交和检查。

### 尚未关闭的五项及精确阻塞

- **#39**：真实且经批准的 DeepSeek/同级模型凭据、成本预算、上传内容与隐私授权、完整实际 SSE/记忆联调。只执行了 MockTransport，无供应商费用。
- **#41**：可连接物理 Android 手机以及型号/系统版本、安装、中文输入、Back、后台、权限与 SQLite 恢复实测；模拟器绝不能充当真机。
- **#42**：双端真实录音和音频路由/中断/试听质量、iOS Swift PCM 编译与实机音频验证（#70）；尚不能宣称主观听感。
- **#43**：角色专属音色来源/明确授权/撤销与删除流程，以及 Android/iOS 真实 ASR/TTS 中文准确率、延迟、网络策略和听感。
- **#44**：Cubism Core 和模型包合法分发许可、正式 Flutter 导入/回滚和 Native 渲染集成、双端动作/生命周期验收。ZIP 预检不是安装器，静态人物不是 Live2D。

本批新合并的功能均保持按 `owner_id + character_id` 隔离的单人物持续时间线设计，不附加个人审批规则到公共仓库规范。未获取付费模型凭据、未部署服务、未上传私人数据、未引入不明确授权的 Cubism SDK 或角色素材。
