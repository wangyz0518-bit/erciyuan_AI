# 模型网关 v0：DeepSeek 回复与 CosyVoice Flash 朗读

> 状态：实现评审中；范围由项目发起人于 2026-11-15 确认
> 适用：本机开发联调，不是多用户生产服务
> 基础：沉浸聊天 PR #16；保留其他未确认的 v1 实体草案

## 分工与数据归属

Flutter 保管现有 SQLite 角色、消息及最近角色。Python/FastAPI 后端保管供应商密钥，调用 DeepSeek 和 CosyVoice。手机发送选中角色的近期已完成对话（最多 20 条、合计 24000 字符），服务端按角色 ID 加入固定角色设定。取消、失败和未完成内容不作为后续上下文。

本版不迁移手机数据库，不把服务端请求日志当作正式消息库，不增加语音消息表。角色与会话目前限 `xing` / `yue` 及 `local-xing` / `local-yue`；没有账号、多设备同步或服务器历史分页。以后接正式 B 核心时必须另行评审，不能直接把本契约冒充完整 v1。

## 连接和认证

本机服务默认仅监听 `127.0.0.1:8787`，使用独立的开发访问令牌：`Authorization: Bearer <GATEWAY_TOKEN>`。供应商 Key 不进入 Flutter。该令牌用于单用户开发隔离，不代表生产用户身份；公开部署前必须补账号鉴权、请求归属、HTTPS、配额与运维方案。

## 接口

| 方法与路径 | 行为 |
| --- | --- |
| `GET /health` | 模式及配置是否存在；不回显 Key、音色 ID |
| `POST /v1/conversations/{conversation_id}/messages` | 输入文字，输出 SSE 事件 |
| `POST /v1/audio/speech` | 仅对已完成的同角色回复合成；返回完整 WAV |
| `POST /v1/requests/{request_id}/cancel` | 本地标记取消，并尽力关闭供应商连接 |
| `POST /v1/audio/transcriptions` | 保留入口，返回 `501 ASR_NOT_IMPLEMENTED`；不读取、存储或上传录音 |

聊天请求：

```json
{
  "request_id": "random-unique-request-0001",
  "character_id": "xing",
  "content": "你好",
  "history": [{"role": "user", "content": "今天想聊聊天"}, {"role": "assistant", "content": "我在听。"}]
}
```

当前输入 1–2000 字符，单条历史最多 6000 字符。历史只允许 user/assistant，角色设定由服务端管理。请求 ID 使用 16–100 位字母、数字、下划线或连字符；客户端生成随机 ID。

SSE 每个 `data:` 行是一个 JSON 对象，以空行分隔。可能有 `: keepalive` 注释：

```text
data: {"event":"message.started","request_id":"random-unique-request-0001"}

data: {"event":"message.delta","delta":"你好"}

data: {"event":"message.completed","request_id":"random-unique-request-0001","content":"你好"}

```

失败或取消终止事件为 `message.failed` / `message.cancelled`，带稳定的 `code`。完成事件必须包含全文；断流、达到生成长度上限、空回复均不能视为成功。DeepSeek 的 `reasoning_content` 不转发、不保存、不朗读。模型名与思考开关可配置，默认 `deepseek-flash`、思考关闭，先验证短回复链路；不是延迟保证。

朗读请求不让客户端重复上传或篡改回复文字：

```json
{
  "request_id": "random-unique-speech-0001",
  "reply_request_id": "random-unique-request-0001",
  "character_id": "xing",
  "expression": "calm"
}
```

服务端确认来源是该角色已完成的聊天，再把完整文字交给 `cosyvoice-v3.5-flash`。表达枚举 calm/happy/comfort/curious；手机当前固定 calm，不由模型猜测用户情绪。音色通过后端配置，开发时两角色可共用已验证音色；不是最终角色声音定案。返回 `audio/wav`，24 kHz、16 bit、单声道。第一版等完整音频返回再播放，不实现音频分片播放。

## 取消、重试和故障

- 同 ID、同参数：服务端重放状态或结果，不再调用供应商；同 ID 不同参数返回 409。
- **网络重传复用 ID；用户主动重试生成使用新 ID**。手机仍复用原用户消息，不重复插入提问。语音重试只重做声音，不重新调用 DeepSeek。
- 服务端请求状态和完成结果写入本机 SQLite；启动时把未完成请求标记为 `SERVER_RESTARTED`，不自动重发付费调用。每次新请求淘汰 24 小时前的已结束记录，最多保留 200 个请求，满后明确拒绝。超过此保留窗口不承诺旧 ID 去重。
- 当前最多 4 个运行任务，仅支持一个后端进程/worker。本版不提供生产并发和计费幂等保证。
- 文字和声音分别有 90 秒服务端超时；客户端也设超时。取消/断线尽力关闭连接，但不能保证供应商停止计算或不计费。
- 停止朗读、切角色、录音、打开其他面板和进入后台会停止播放，并使迟到声音无效；正在生成的声音同时发送取消请求。
- 文字保存成功后才触发声音。声音失败保留文字，可单独重试。退出后不自动重播；历史朗读与语音跨重启恢复不在本版范围。
- 原有手动录音仍只在本机试听；不因接入声音模型而自动上传。

HTTP 错误格式为 `{"error":{"code":"COMPLETED_REPLY_REQUIRED","message":"请求未完成，请检查状态后重试。"}}`。校验失败不回显输入；供应商错误不原样透出 Key、连接地址或音色 ID。常见码包括 UNAUTHORIZED、INVALID_REQUEST、REQUEST_ID_CONFLICT、MODEL_TIMEOUT、MODEL_AUTH_FAILED、MODEL_INCOMPLETE、VOICE_UNAVAILABLE、VOICE_TIMEOUT、SERVER_RESTARTED、ASR_NOT_IMPLEMENTED。

## 与旧草案的关系

本文件是已确认范围的独立实现补充。旧 README 的通用“重试复用 ID”在本版细分为传输重传与主动重新生成；旧草案中角色增删、服务器正式会话/消息、通用生成任务仍未实现。现有手机 Message 字段和状态值不改成旧草案的字段，避免未经评审的数据迁移。

## 来源

- [DeepSeek 调用与流式入口](https://api-docs.deepseek.com/)
- [DeepSeek 思考内容与正式回复](https://api-docs.deepseek.com/guides/thinking_mode/)
- [CosyVoice WebSocket 协议](https://help.aliyun.com/en/model-studio/cosyvoice-websocket-api)
- 仓库声音实验 `codex/d-voice-desktop-poc` / `b8fc84e`，复用已有 Flash 音色配置，不重新创建音色。
