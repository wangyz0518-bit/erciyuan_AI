# Issue #38：正式 AI 服务及后端方案评估

> 日期：2026-11-18
> 状态：设计交付已写入本 Issue 独立 PR；GitHub/文档检查完成后才合并
> 前置：#35 Flutter、#36 SQLite 原始层、#47 三层离线记忆已实现
> 范围：只评估后端与协议，不调用收费供应商，不部署公网或提交凭据

## 1. 代码/资产评估

| 来源 | 保留与复用 | 不可直接采用 | 下游归属 |
| --- | --- | --- | --- |
| PR #21 | FastAPI provider、SSE 事件、DeepSeek 取消/重试/测试 | 固定 xing/yue、全局请求账本、单一开发令牌和基于 conversation_id 的 API | #39 |
| PR #22 | v2 WS/PCM、音频资源/迟到事件、断线查询经验 | iOS PCM 未验、WS 全语音耦合、单用户权限 | #42/#43 |
| PR #24 | 音色绑定、任务幂等、unknown 结果查询 | voice_profiles SQLite 缺多用户授权/云端删除 | #43 |
| PR #18/#19/#23 | 语音对比与负面路线 | 不当作 TTS/ASR 的最终商业 SLA | #43 |
| main #36/#47 | PersonScope、RawEvent、三层来源/身份和 ContextAssembler | 本机 ownerId 不等于服务器身份认证 | #39 |

这些外部 PR 没有被改写/合并；复用必须按单独增量与许可证、安全条件判断。

## 2. 交付文件

- [docs/design/ai-service-backend-architecture-20261118.md](../docs/design/ai-service-backend-architecture-20261118.md)：部署/鉴权/租户/隐私/复用矩阵及 SSE/WS 取舍。
- [docs/接口/person-text-gateway-v1-20261118.md](../docs/接口/person-text-gateway-v1-20261118.md)：人物路径、上下文快照、状态、错误、SSE、取消、幂等及协议负向测试。
- [docs/decisions/0005-person-scoped-model-gateway.md](../docs/decisions/0005-person-scoped-model-gateway.md)：推荐逐步重用 FastAPI provider，明确为提议，生产授权尚未满足。
- 所属 docs/ 目录索引应同步更新；旧面向多 Conversation 的接口草案明确标注被人物契约覆盖的范围。

## 3. 验收

- [x] 检查 #21/#22/#24 核心源码与旧协议，明确复用/适配/不采用。
- [x] 记录认证、授权、owner+character 作用域、密钥与数据最小化的完整边界。
- [x] 设计 request_id 指纹、同 ID 重传/不同参数冲突、取消/重试、unknown、服务重启和迟到事件。
- [x] 设计稳定人物前缀、离线记忆检索的 ContextSnapshot 及有限外发，强调来源 ID 不能替代在线认证。
- [x] 给出开发/生产边界、SSE/WS 决策、可替换供应商与数据保留策略。
- [ ] 合并前确认文档 Markdown 相对链接、JSON 合成示例、差异无敏感信息、PR 作者与 GitHub 规则。

## 4. 未实现与下游

#38 为文档/架构评估，不存在可声明已通过的真实模型集成测试。#39 承接实际 provider 适配、服务鉴权、headless Flutter 联调和 Token/缓存/成本/记忆质量测量；不存在凭据或费用授权时，只能 Mock 测试并标记真实项未完成。

#37 正式 UI、#40/#41 双平台、#42/#43 音频/语音、#44 人物动画互不冒充。此设计不自动取得公网部署、付费 API、用户私人数据传输或第三方素材使用授权。