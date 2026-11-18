# 人物中心文字模型网关协议 v1（Issue #38 设计契约）

> 状态：待 #39 实现和协议级回归；当前是设计，不是已上线 API
> 日期：2026-11-18
> 相关：[后端方案](../design/ai-service-backend-architecture-20261118.md)、[ADR-0005](../decisions/0005-person-scoped-model-gateway.md)、[三层记忆](../design/person-memory-data-contract-20261118.md)

## 1. 原则

正式服务提供“对某个人物的一个生成任务”，不提供创建 Conversation/Session 的产品 API。人物唯一逻辑时间线属于 SQLite RawEvent；模型 request、SSE 连接、内部窗口、记忆归档和 provider session 都不生成新用户会话。

- 所有请求经过 HTTPS、有效身份认证并校验人物使用权；开发回环可使用长随机令牌，但不能公网部署。
- 服务端从认证主体推导 owner_id；任何客户端自报 owner_id 不构成授权。
- 客户端 #47 构造稳定人物身份前缀，带当前问题、近期已完成 RawEvent、相关摘要和必要的来源 ID；发送前采取数据最小化。
- 不依赖供应商私有对话 Session；供应商端缓存/思考内容不进入用户可导出原始消息。
- 协议预留向后兼容的版本字段，但未知关键字段应被拒绝或按显式升级策略处理，不能静默丢掉安全约束。

## 2. 正式端点（待实现）

| 方法 | 路径 | 行为 | 返回 |
| --- | --- | --- | --- |
| POST | /v1/characters/{character_id}/turns | 接受新的或重复的一个文字模型请求 | text/event-stream；状态事件 |
| GET | /v1/characters/{character_id}/turns/{request_id} | 查询本已认证人物的请求终态，断线后只读恢复 | 200 JSON；不存在 404 |
| POST | /v1/characters/{character_id}/turns/{request_id}/cancel | 尽力取消同一人物进行中的模型生成 | 202/200 JSON，幂等 |
| GET | /health | 不暴露 Key、音色 ID、个人信息的存活/能力检查 | 200 JSON |

旧 PoC 的 /v1/conversations/{conversation_id}/messages 和 /v2/conversations/{conversation_id}/stream 仅作参考/兼容入口，不进入正式 App，也不等价于每人物新增聊天。

## 3. 发送输入样例（全部为合成测试数据）

请求头：Authorization: Bearer LOCAL_OR_AUTHENTICATED_ACCESS_TOKEN；Content-Type: application/json；Accept: text/event-stream。

以下 JSON 可直接解析。真实 Token 由后端认证模块产生；示例 access token 不是真实密钥。

~~~json
{
  "protocol_version": 1,
  "request_id": "request-test-star-000001",
  "character_id": "star",
  "current_input": {
    "event_id": "event-0042",
    "content": "上次聊过的茶是什么？"
  },
  "context": {
    "prefix_version": "person-prefix-v1",
    "identity_version": 3,
    "stable_prefix": "person-prefix-v1\nowner=local-example\ncharacter=star\nbase={}\nidentity_version=3\napproved_state={}",
    "selected_summaries": [
      {
        "summary_id": "summary-archive-001",
        "text": "user: 喜欢乌龙茶",
        "source_event_ids": ["event-0001", "event-0002"]
      }
    ],
    "recent_events": [
      {
        "event_id": "event-0041",
        "role": "assistant",
        "content": "我们之前聊过喝茶。"
      }
    ],
    "expanded_sources": []
  },
  "model_profile": "default-text",
  "retry_of": null
}
~~~

正式 App **不应**为网络请求上传所有时间线、全量导出文件、其他人物摘要或默认录音。服务端可以重新校验 context 内 character_id 与路径、字段大小与列表长度，但不能在未持有同源事实的情况下谎称已经独立验证本地 source_event_ids 的真实性。前缀文本是模型上下文，不是后端鉴权、权限或系统配置指令。

输入约束（初版建议，在 #39 以实现测试确定）：request_id 为 16–100 位安全 ASCII，character_id 为规范化不含路径分隔符的稳定 ID；current_input 为 1–2000 字符；recent_events 最多 20 项；selected_summaries 最多 8 项；每项 summary 最多 2000 字符、source_event_ids 最多 50 项；stable_prefix 最多 12000 字符；所有动态内容合计最多 24000 字符；HTTP 实体总量最大 64 KiB。超限统一返回 422，不截断重要身份或悄悄改写输入。未来扩大限额应考虑费用、缓存和隐私影响。

## 4. SSE 事件

SSE 以 UTF-8 编码，响应头 Content-Type: text/event-stream、Cache-Control: no-store。每条 data 包装一个 JSON 对象；支持保活注释。事件不需要创建用户新 Session。

~~~text
data: {"event":"message.started","request_id":"request-test-star-000001","character_id":"star"}

data: {"event":"message.delta","request_id":"request-test-star-000001","delta":"我记得"}

data: {"event":"message.completed","request_id":"request-test-star-000001","character_id":"star","content":"你说喜欢乌龙茶。","usage":{"input_tokens":null,"output_tokens":null,"cached_tokens":null}}

~~~

| 事件 | 核心字段 | 客户端处理 |
| --- | --- | --- |
| message.started | request_id、character_id | 标记运行中，不能写入完成事件 |
| message.delta | request_id、delta | 仅展示暂存文本，不视为持久事实 |
| message.completed | request_id、character_id、完整 content、可选 usage | 验证 scope 和 request_id，完成本地事务写入后标为 completed |
| message.failed | request_id、稳定 code | 丢弃当前完成候选，明确失败 |
| message.cancelled | request_id | 禁止迟到结果恢复 |
| message.unknown | request_id、code | 仅查询状态，不自动重新触发收费请求 |

真实 provider 的 usage 可以返回 input_tokens、output_tokens、cached_tokens 和耗时；供应商未提供时必须为 null 或 absent，不得伪造 0%/100% 缓存命中。DeepSeek 的 reasoning_content 不转发、持久化或朗读。

## 5. 幂等与状态查询

键空间：已认证 owner + character_id + request_id。一个请求绑定规范化输入、上下文版本与模型配置 fingerprint。

- 相同 ID、同 fingerprint：只返回已有状态或记录的完成结果，不重复收费调用。
- 相同 ID、不同 fingerprint：409 REQUEST_ID_CONFLICT。
- 主动重新生成：新 request_id，明确 retry_of；不是把旧请求改参数。
- 网络恢复：GET status 查询，不自动重新请求模型。
- 未知供应商结果：unknown；用户或服务端核实后才能决定是否主动重试。
- 取消是尽力控制，已执行供应商调用可能计费；完成后取消不会抹掉已成功提交的原始事实。
- 旧请求的结果不能覆盖新人物、新页面、已取消操作或新生成任务。

状态查询 JSON 示例：

~~~json
{
  "request_id": "request-test-star-000001",
  "character_id": "star",
  "status": "completed",
  "content": "你说喜欢乌龙茶。",
  "error": null,
  "usage": null
}
~~~

服务端短期状态/完成结果 TTL（本机可沿用 24 小时）与生产数据保留策略必须明确区分，不得当作长期聊天历史或用户备份。请求本地终态由 #36 RawEvent + GenerationTask 保证；#47 记忆系统只读完成事实。

## 6. 认证、隐私和错误

所有状态查询、取消和重放都必须重新验证当前认证用户对人物的权限，拒绝 IDOR 访问。外部模型内容应通过 HTTPS，并在用户有明确外发告知和适当控制后才发送。Flutter 不保存供应商 API Key。真实日志默认不记录正文、稳定前缀、录音或全量源引用。

稳定错误格式：

~~~json
{
  "error": {
    "code": "REQUEST_ID_CONFLICT",
    "message": "请求状态与原参数不一致",
    "request_id": "request-test-star-000001"
  }
}
~~~

建议至少覆盖：UNAUTHORIZED (401)、FORBIDDEN_CHARACTER (403)、REQUEST_NOT_FOUND (404)、REQUEST_ID_CONFLICT (409)、INPUT_TOO_LARGE/INVALID_REQUEST (422)、RATE_LIMITED (429)、MODEL_NOT_CONFIGURED/MODEL_UNAVAILABLE (503)、MODEL_TIMEOUT (504)、MODEL_INCOMPLETE、SERVER_RESTARTED、RESULT_UNKNOWN、REQUEST_CANCELLED。

## 7. #39 必须实施的协议负向测试

1. 未授权 Token、不同 owner 使用相同 character_id、重放他人 request_id、伪造 owner_id：必须拒绝，且不泄露是否存在他人内容。
2. 同 ID 不同 prompt/content/identity_version：409；同 ID 相同 fingerprint：不产生第二次供应商调用。
3. 断流、finish_reason 非 stop、空回复、超时、取消：不能写入 completed 的 RawEvent；重新进入人物时不污染后续 Context。
4. 切换人物后迟到 delta、completed、取消确认：被丢弃或回到正确原人物的请求，不串人物。
5. 模型 Key 不进入 Flutter 构建/日志/错误；服务端不在响应中暴露内部供应商错误详细内容。
6. SSE chunk 分裂、保活、重复事件、网络重连时查询状态：结果可预测，不自动产生额外付费调用。
7. 用户本地完整导出保持原始层、记忆层、身份层完整；网关任务状态并非导出的替代品。

上述示例和接口只用于审查、Mock/contract 测试；在 #39 实际实现并取得相应凭据前，不代表外部服务真实可用。