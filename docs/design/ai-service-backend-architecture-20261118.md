# 人物中心 AI 服务与后端架构评估（Issue #38）

> 日期：2026-11-18
> 状态：已完成的架构评估文档；不是生产部署或真实模型验收
> 依据：[ADR-0004](../decisions/0004-person-centered-memory-architecture.md)、[人物记忆数据契约](person-memory-data-contract-20261118.md)、[#47 记忆内核](../../plan/issue-47-memory-implementation-20261118.md)
> 配套：[文字模型协议 v1](../接口/person-text-gateway-v1-20261118.md)、[ADR-0005](../decisions/0005-person-scoped-model-gateway.md)

## 1. 建议结论

**复用既有 Python/FastAPI 模型网关的 provider、流式请求和任务状态机制，而不是从零重写；正式产品必须新建以已认证 owner + character 为数据边界的 API 适配层。**

文字 MVP 选用 HTTP + Server-Sent Events（SSE），音频和双向实时能力在 #42/#43 按需复用 WebSocket v2/PCM。现有 Flutter SQLite 是每个人物唯一时间线的权威事实层；#47 在本地组织人物身份、摘要与近期原文，#39 网关仅接受本次必要的上下文快照、调用供应商和短期保存状态，不保存新的用户可见 Conversation。

开发网关保持 127.0.0.1 回环与明确 Mock 模式。未批准生产鉴权、外部密钥、费用预算或真实数据传输前，不开放公网服务，也不发起真实计费模型调用。

## 2. 现有 PR 增量复用矩阵

| 来源 | 复用的实际成果 | 需要改造或暂不采用 | 结论 |
| --- | --- | --- | --- |
| [#21 DeepSeek + CosyVoice](https://github.com/wangyz0518-bit/erciyuan_AI/pull/21) | services/model_gateway/gateway/providers.py 的流式 DeepSeek provider、超时/错误映射；app.py 的 SSE、取消与幂等；tests/test_gateway.py | 旧 conversation_id 只支持 local-xing/local-yue，内置 PERSONAS，使用单一 GATEWAY_TOKEN、全局 request ledger、客户端自填历史；不提供账户鉴权/角色权限 | **#39 选择性移植 provider、SSE、测试；重新实现租户鉴权与记忆 Context 适配** |
| [#22 服务端流式语音](https://github.com/wangyz0518-bit/erciyuan_AI/pull/22) | gateway/streaming.py、speech_pool.py、PCM 顺序/偏移校验、连接复用、迟到事件拒绝与测试 | v2 语音仍是本机单用户；iOS PCM 和生产并发未验收 | **文字主链先不引入 WebSocket；音频模块由 #42/#43 复用** |
| [#24 录音音色复刻](https://github.com/wangyz0518-bit/erciyuan_AI/pull/24) | voice_enrollment.py、voice_profiles.py、voice_store.py、test_voice_profiles.py 的未知结果查询、幂等任务、绑定版本 | voice_profiles.sqlite 当前无独立用户权限；云端音色删除、录音合法授权和租户隔离不足 | **#43 复用核心状态机但补齐隐私/授权/删除** |
| #18/#19/#23 | 供应商对比实验及音色微调的负面结果 | 旧实验不等于商业 SLA；#23 继续暂停 | **只作为候选选择依据** |
| main #35/#36/#47 | 正式 Flutter、人 物 scope、SQLite RawEvent、Archive、MemorySummary、Identity、全量导出 | 本机 owner_id 是数据分区，不是在线登录身份；离线规则摘要不证明真实语义质量 | **直接采用已实现的数据契约** |

#21、#22、#24 的 Changed Files 包含继承的旧分支代码，不代表每个 PR 都独立重新开发了全部文件。#39 必须按原提交和路径增量选择性移植，而不是整体合并历史 PoC 分支。

## 3. 产品与数据不变量

1. 每 owner+character 只有一条持续逻辑时间线。内部 request_id、provider session、归档片段、WebSocket 连接或服务端任务都不是“新聊天会话”。
2. 原始消息长期保存在用户控制的本地 SQLite，归档不删除原始事件。摘要必须有来源，动态人物身份必须明确确认并有版本。
3. 本地 ContextAssembler 应把稳定、版本化人物身份前缀放在动态检索摘要和近期原文之前。取消/失败的生成绝不进入当前有效上下文。
4. 服务端只接收用户授权发送的必要上下文快照，默认不上传本地全量历史或导出文件。来源 ID 只是客户端声明的证据定位，不是服务端可据以授权的凭证；若要独立验证来源，必须另建有授权的同步/签名方案。
5. 服务端需对快照最大条目数、单条长度、角色、来源引用数量、编码和总字节数做硬限制，禁止把检索文本当作高可信系统指令或身份认证材料。

## 4. 鉴权、租户与网络边界

**开发模式**：允许单机长随机 GATEWAY_TOKEN 和回环 HTTP；令牌只能保护本机调试服务，不等于正式用户身份。不得把云供应商 API Key 编进 Flutter 包、音色文件或日志。

**多用户模式（待实现与部署授权）**：HTTPS/TLS、受信任的服务端会话或经验证的身份提供商 Token。网关从已认证主体推导 owner_id，检查其对指定 character_id 的操作权限；不能信任 JSON、URL 或客户端本地 owner_id 来作身份认证。请求重放、取消、查询状态、音色访问和资源删除每次都必须重新做权限验证。

服务端请求主键与速率/缓存键至少由 authenticated_owner、character_id、request_id 构成，并约束模型内容的 fingerprint（输入、人物身份版本、上下文版本、模型参数）。同 ID + 同内容只查询/重放已有结果；同 ID 不同参数返回 409。不同用户或人物即使 request_id 相同，也不能互相读写或返回缓存。

Model Provider Key 只在服务端受控环境配置。日志仅记录关联哈希、状态、错误码、延迟及可脱敏的用量指标；默认不记录人物身份前缀、消息正文、录音或完整来源。需定义生产保留期限、删除机制、访问审计和费用配额后才能上线。

## 5. API 和模型层分工

| 层 | 职责 | 不能做的事 |
| --- | --- | --- |
| Flutter PersonDatabase / #47 | 唯一人物时间线、原始事实、归档/摘要/来源/身份版本、稳定上下文、用户全量导出 | 把本地 ownerId 假装为服务器认证 |
| Flutter ModelGatewayAdapter / #39 | 构造有限输入快照、生成随机 request_id、SSE 解析、取消/重试、保存完整正式结果 | 保存供应商 Key；把失败/取消草稿当 completed |
| FastAPI authentication + authorization | 验证身份并派生 owner、验证 character 权限、限流和配额 | 从用户填的 owner_id 直接派生租户归属 |
| Scoped request ledger | 请求 fingerprint、状态、幂等、TTL、重连查询、未知结果恢复 | 因断线自动再次发起收费请求 |
| LLMProvider | 可切换的 DeepSeek/替代服务、可取消流式 API、供应商错误与 Token/缓存指标 | 将供应商 session 当作人物时间线 ID |
| AudioAdapter / #43 | 经授权的 TTS/ASR、角色声音资源、取消和删除 | 默认上传用户录音或跨人物共享音色 |

正式文本入口为人物作用域的 POST /v1/characters/{character_id}/turns，GET /v1/characters/{character_id}/turns/{request_id} 和 POST /v1/characters/{character_id}/turns/{request_id}/cancel。旧的 /v1/conversations/{conversation_id}/messages 仅保留为本机 PoC 兼容研究，不进入正式 UI。

## 6. 请求状态与可靠性

- 接受请求后返回 started；流式 delta 仅用于预览，只有包含完整 content 的 completed 才能持久写入 assistant RawEvent。
- failed/cancelled/unknown 都不能进入有效记忆上下文。断线、空输出、非正常 finish_reason、超时及截断均不能当作 completed。
- 网络重传使用同 request_id；用户主动重新生成必须用新 request_id，并可记录 retryOf，不重复原提问。服务端结果未知时只查询状态，不自动再次调用计费供应商。
- 取消是尽力控制；已经发生的 Token/语音计费可能无法撤销。切换人物、退出或重连时，迟到的 delta/completed/音频都不得污染另一人物。
- 服务重启后在途任务转为 unknown/failed-with-recovery，明确查询后才能恢复；不假设多个进程间共享内存 ledger 就能做到幂等。
- 请求状态、缓存与计费记录应定义 TTL、最大并发、全局和每租户配额以及可观测错误码；真实保证须 #39 的测试和部署环境验证。

## 7. 传输与供应商对比

| 备选 | 优点 | 问题/限制 | 处理 |
| --- | --- | --- | --- |
| HTTP + SSE 文字 | 直接复用 #21 的流式解析、取消和错误测试，调试简单 | 不适合双向高频音频 | **文字 MVP 首选** |
| WebSocket + PCM | #22 有 Android 实际链路与连接指标 | iOS PCM、弱网和多租户未验收 | **语音阶段按需移植** |
| 端侧模型 | 可降低云端数据传输 | 手机功耗/质量/尺寸未知 | 后续研究 |
| 旧 PoC 直接公开 | 接入快 | 存在身份、配额、审计、安全风险 | **禁止** |

DeepSeek 只是已有 PoC 测过的首个候选 provider，不是最终独家供应商。#39 才在获授权密钥和额度后实测真实长对话质量、人物一致性、来源引用召回、输入/输出/缓存 Token、缓存命中、费用和延迟；Mock 不得用于声称上述指标通过。

## 8. 风险与验收归属

| 风险 | 最低控制或负向测试 | 验收阶段 |
| --- | --- | --- |
| IDOR 跨 owner/人物 | 伪造 owner_id/character_id、改 path 和重放其他主体 request_id 全部拒绝 | #39 |
| 提示注入/记忆伪造 | 不可信检索内容不得覆盖已确认基础人物身份或服务端认证策略 | #39 |
| 资金风险 | per-owner 限额、超时、取消、未知结果不重复计费、费用日志脱敏 | #39 |
| Key/隐私泄露 | 服务端 Key；最小上下文、日志不含正文、权限/TTL/删除检查 | #39 |
| 声音跨人物 | owner-scoped voice profile + 授权 + 云端删除证据 | #43 |
| 平台不兼容 | Android/iOS 的真实构建/播放证据各自报告 | #40～#43 |

**#38 的完成标准是评审、架构和协议契约可追溯，不代表已实现生产鉴权、SLA、真实模型接通或公网发布。** 涉及付费 API、真实用户数据、外部部署和许可证仍需分别授权。