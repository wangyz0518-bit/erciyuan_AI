# 接口契约（v1 草案）

> 状态：草案，待 A/B/C/D 四条工作线一起确认；未确认前不作为实现依据。
> 日期：2026-11-11

本文定义客户端与对话服务之间的最小接口，用于并行开发时对齐字段和失败语义。具体协议（REST/SSE/WebSocket）、鉴权方式和部署形态由技术方案确定后补充。

## 独立资源契约

| 文档 | 用途 | 状态 |
| --- | --- | --- |
| [人物资源包契约 v0.1](avatar-package-contract-20261113.md) | 约定制作方交给 App 的 Live2D ZIP、动作映射、兼容范围和验收；不修改下文服务端实体 | 已确认用于离线联调，Android 导入器已实现 |
| [人物包制作任务书](avatar-package-producer-brief-20261113.md) | 可转发给制作方，附 Schema 与非可运行描述文件示例 | v0.1 联调用 |

## 通用约定

- 所有时间使用 ISO 8601 UTC，例如 `2026-11-11T12:00:00Z`。
- 所有 ID 使用字符串，客户端不解析其内部结构。
- 写请求携带 `request_id`，服务端据此去重；网络重传不得重复保存消息或重复调用模型。
- 列表接口使用游标分页：`?cursor=...&limit=...`。
- 错误统一使用下面的结构，不返回裸字符串。
- 接口路径暂以 `/v1` 为前缀，最终以服务端实现为准。

## 错误结构

```json
{
  "error": {
    "code": "MODEL_TIMEOUT",
    "message": "对话生成超时",
    "request_id": "req_01",
    "details": {}
  }
}
```

`code` 使用稳定的大写标识，客户端按 `code` 分支处理，不匹配 `message` 文本。

## 实体

### Character 角色

```json
{
  "id": "char_01",
  "name": "角色名",
  "avatar_asset_id": "asset_01",
  "persona": "性格与设定文本",
  "voice_id": "voice_01",
  "created_at": "2026-11-11T12:00:00Z",
  "updated_at": "2026-11-11T12:00:00Z"
}
```

### Conversation 会话

```json
{
  "id": "conv_01",
  "character_id": "char_01",
  "title": "初次见面",
  "created_at": "2026-11-11T12:00:00Z",
  "updated_at": "2026-11-11T12:00:00Z"
}
```

### Message 消息

```json
{
  "id": "msg_01",
  "conversation_id": "conv_01",
  "role": "assistant",
  "content": "你好呀。",
  "status": "completed",
  "request_id": "req_01",
  "created_at": "2026-11-11T12:00:00Z"
}
```

`role`：`user` / `assistant`。
`status`：`pending` / `streaming` / `completed` / `failed` / `cancelled`。

### GenerationTask 生成任务

用于形象、表情、语音等异步生成。

```json
{
  "id": "gen_01",
  "type": "tts",
  "status": "running",
  "input": {},
  "output": null,
  "error": null,
  "created_at": "2026-11-11T12:00:00Z",
  "updated_at": "2026-11-11T12:00:00Z"
}
```

`type`：`image` / `emotion` / `tts` / `asr`。
`status`：`queued` / `running` / `succeeded` / `failed` / `cancelled`。

### AudioAsset 音频结果

```json
{
  "id": "audio_01",
  "url": "https://example.com/audio/audio_01.mp3",
  "format": "mp3",
  "duration_ms": 3200,
  "sample_rate": 44100
}
```

## 接口

### 角色

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/v1/characters` | 角色列表 |
| POST | `/v1/characters` | 创建角色 |
| GET | `/v1/characters/{id}` | 角色详情 |
| PATCH | `/v1/characters/{id}` | 更新角色 |

### 会话与消息

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/v1/conversations` | 创建会话 |
| GET | `/v1/conversations/{id}` | 会话详情 |
| GET | `/v1/conversations/{id}/messages` | 消息列表，支持游标分页 |
| POST | `/v1/conversations/{id}/messages` | 发送用户消息，返回流式回复 |

发送消息请求：

```json
{
  "request_id": "req_01",
  "content": "今天过得怎么样？"
}
```

### 生成任务

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/v1/generations` | 创建生成任务 |
| GET | `/v1/generations/{id}` | 查询任务状态 |
| POST | `/v1/generations/{id}/cancel` | 取消任务 |

### 语音

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/v1/audio/transcriptions` | 录音转文字 |
| POST | `/v1/audio/speech` | 文字转语音 |

## 流式回复事件

发送消息后，服务端以 SSE 或 WebSocket 推送事件；具体协议待定。事件类型：

| 事件 | 含义 |
| --- | --- |
| `message.started` | 回复开始，返回 `message_id` |
| `message.delta` | 增量文本 |
| `message.completed` | 回复完成，返回完整消息 |
| `message.failed` | 失败，返回错误结构 |
| `message.cancelled` | 已取消 |

```text
event: message.delta
data: {"message_id":"msg_01","delta":"你"}
```

客户端取消后，应忽略迟到的 `delta` 和 `completed`，不写入本地记录。

## 取消与重试

- 客户端切换角色、退出会话或用户主动取消时，停止当前流并调用取消接口。
- 服务端收到取消后停止生成；已产生的部分内容不写入正式消息，除非产品明确要求保留草稿。
- 客户端重试必须复用同一个 `request_id`，由服务端保证幂等。
- 文字成功而语音失败时保留文字，语音可单独重试。

## 待确认项

- 鉴权方式与令牌刷新。
- 流式协议选 SSE 还是 WebSocket。
- 音频格式、采样率与大小限制。
- 形象资源使用 URL 还是资源 ID + 下载接口。
- 模型供应商、用量和计费字段是否暴露给客户端。
- 离线缓存与增量同步策略。

## 变更流程

1. 修改字段或语义前，在 Issue 或 PR 中说明影响范围。
2. 同步更新本文、调用方和相关验收样例。
3. 删除或重命名字段视为不兼容变更，需要四条工作线确认。
