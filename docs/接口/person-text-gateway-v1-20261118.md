# 人物中心文字模型网关协议 v1（Issue #38 设计契约 / #39 实施校正）

> 状态：#39 开发实现中；以实际测试和 CI 为准，不代表公网部署或真实模型联调已通过。
> 日期：2026-11-18
> 相关：后端方案、ADR-0005、三层记忆数据契约。

## 1. 原则

正式服务提供“对某个人物的一个生成任务”，不提供创建 Conversation/Session 的产品 API。人物唯一逻辑时间线属于 SQLite RawEvent；模型 request、SSE 连接、内部窗口、记忆归档和 provider session 都不生成新用户会话。

- 所有请求经过身份认证，并校验当前主体对人物的使用权；开发回环可使用长随机令牌和显式人物 allowlist，但不能公网部署。
- 服务端从认证主体推导 owner_id；客户端自报 owner_id 不构成授权。
- 客户端 #47 构造稳定人物身份前缀，带当前问题、近期已完成 RawEvent、相关摘要和必要的来源 ID；发送前采取数据最小化。
- 稳定身份前缀是人物描述数据，不是服务端策略、权限或系统指令。
- 不依赖供应商私有对话 Session；供应商端缓存/思考内容不进入用户可导出原始消息。
- 未知关键字段应被拒绝或按显式升级策略处理，不能静默丢掉安全约束。

## 2. 正式端点

| 方法 | 路径 | 行为 |
| --- | --- | --- |
| POST | /v1/characters/{character_id}/turns | 接受新的或重复的一个文字模型请求，返回 SSE |
| GET | /v1/characters/{character_id}/turns/{request_id} | 查询同一已认证人物的请求终态 |
| POST | /v1/characters/{character_id}/turns/{request_id}/cancel | 尽力取消同一人物进行中的模型生成 |
| GET | /health | 不暴露 Key、音色 ID、个人信息的能力检查 |

## 3. 发送输入与上下文

请求包含 protocol_version、request_id、character_id、current_input、context、model_profile 和可选 retry_of。context 字段为 prefix_version、identity_version、stable_prefix、selected_summaries、recent_events 和 expanded_sources。

字段边界：
- request_id：16–100 位安全 ASCII；character_id：1–80 位安全 ASCII。
- current_input：1–2000 字符。
- stable_prefix：最多 12000 字符。
- selected_summaries：最多 8 项；每项摘要最多 2000 字符、来源 ID 最多 50 项。
- recent_events 和 expanded_sources：各最多 20 项；每项内容最多 6000 字符。
- 动态上下文最多 24000 字符、最多 64 KiB UTF-8；turn JSON 实体最多 64 KiB。超限拒绝，不截断重要身份或静默改写输入。
- 不上传全量时间线、导出文件、其他人物摘要或默认录音。

### 可信边界

服务端只把固定、服务端拥有的策略放入 provider system role。

stable_prefix、摘要、来源事件和近期历史全部是客户端提供的上下文数据，必须作为不可信内容序列化在普通 user 内容中。历史事件中的 role 仅为描述性元数据；不能将客户端声称的 assistant 事件直接转换成 provider assistant role。expanded_sources 必须真正参与上下文装配，并与摘要来源一起标记为不可信参考数据。

客户端提供的 source_event_ids 无法由当前无服务端原始数据库的开发网关独立证明真实性。网关不应声称已验证这些 ID；其权威事实来源仍是本地 #36/#47 数据库。

## 4. SSE 事件

每条 data 包装一个 JSON 对象，至少包含 event 和 request_id。支持：
- message.started：标记运行中。
- message.delta：渐进展示，不能作为已持久化事实。
- message.completed：完整 content 和 character_id；客户端验证 request_id/scope 后，在本地事务中写入完成事件。
- message.failed：稳定错误 code；丢弃未完成候选。
- message.cancelled：禁止迟到结果恢复。
- message.unknown：结果无法确认，查询状态，不自动重发收费请求。
- turn.status：重复 request_id 时返回已有状态，不再次调用 Provider。

DeepSeek reasoning_content 不转发、不持久化、不朗读。Provider usage 无数据时必须为 null 或 absent，不得伪造 Token 或缓存指标。

## 5. 幂等、取消和状态

幂等键：已认证 owner + character_id + request_id。相同 ID、相同 fingerprint 返回已有状态；相同 ID、不同 fingerprint 返回 409 REQUEST_ID_CONFLICT。主动重试必须使用新 request_id，并通过 retry_of 指向原请求。

取消会将 ledger 状态改为 cancelled，并尝试取消同一进程中的 Provider task/HTTP 请求。取消是尽力操作，已发出的供应商请求可能已计费。断开 SSE 连接会终止本地 Provider task 并把请求标记为 unknown；服务重启时，残留 running 也转为 unknown。unknown 不等于失败，不可自动重新发起请求。

当前 SQLite ledger 和 active-task cancellation registry 是单进程开发方案。SQLite 唯一约束保护 request ID，WAL 用于本地读写；多进程部署、分布式取消、生产限流与生产级认证不在本 Issue 的开发网关中实现。

## 6. 错误与隐私

稳定错误至少包括 UNAUTHORIZED、FORBIDDEN_CHARACTER、REQUEST_NOT_FOUND、REQUEST_ID_CONFLICT、INVALID_REQUEST、CONTEXT_TOO_LARGE、REQUEST_TOO_LARGE、MODEL_NOT_CONFIGURED、MODEL_UNAVAILABLE、MODEL_TIMEOUT、MODEL_INCOMPLETE、MODEL_EMPTY、MODEL_REPLY_TOO_LONG、SERVER_RESTARTED、RESULT_UNKNOWN、REQUEST_CANCELLED。

Flutter 不保存供应商 API Key。真实日志默认不记录正文、稳定前缀、录音或全量源引用。外部模型调用须有明确授权；本次开发及测试仅使用 Mock 和 HTTP Mock，不调用收费 API。

## 7. #39 协议负向测试

1. 无效 Token、越权人物、重放他人 request_id：拒绝且不泄露其他主体状态。
2. 同 ID 不同参数：409；同 ID 同 fingerprint：不产生第二次 Provider 调用。
3. 断流、finish_reason 非 stop、空回复、超时、取消：不能写入 completed assistant RawEvent。
4. 切换人物后迟到 delta/completed 只能归属于原人物请求，不能污染当前人物。
5. Key 不进入 Flutter 构建/日志/错误；Provider 内部错误详情不暴露给客户端。
6. SSE chunk 分裂、断线查询状态、重复事件：不自动产生额外付费调用。
7. 原始记录、记忆摘要、来源和身份版本继续由 #36/#47 导出；网关状态账本不是用户历史备份。

## 8. 朗读已完成的人物回复

`POST /v1/characters/{character_id}/turns/{request_id}/speech` 沿用文字请求的 Bearer 开发令牌，请求体为空。服务端从该 owner、人物和请求的已完成账本记录取文字，按人物绑定选择音色。该调用只做语音合成。客户端在本人物页面明确开启后，为新完成的回复调用一次；切换人物、关闭朗读或退入后台即停止。

成功响应是 `application/x-ndjson`，`X-Voice-Mode` 为 `live` 或 `demo`。每行是一个 JSON 对象。音频行的 `pcm` 为 base64 编码的 24 kHz 单声道 PCM16LE（每帧最多 9600 字节），成功以 `{"done":true}` 结束。流内失败以 `{"error":"VOICE_UNAVAILABLE"}` 结束。客户端遇到错误或缺失完成帧时停止播放，保留已保存的文字。

未授权、越权、缺少请求或绑定时返回 4xx，未配置语音服务时返回 503。每个已完成回复最多受理一次合成。重传返回 409，断开后不自动重新计费。开发联调只为本机测试 owner 配置音色。
