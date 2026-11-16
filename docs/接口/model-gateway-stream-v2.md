# 模型网关 v2：服务器统一调度文字和声音

> 状态：按用户确认方案实现，待评审；未合并
> 更新：2026-11-15
> 范围：本机单用户开发网关、Android 模拟器；不是生产多租户协议

## 流程与兼容

App 发一次 `chat.send`。服务器复用 HTTP 客户端请求 DeepSeek，只使用最终回答内容，不朗读推理过程；等完整回复、正常结束后，先发 `message.completed`，随后自动调用 CosyVoice Flash。音频边生成边传输。App 必须先保存完整文字，才能消费已缓冲的声音；本地保存失败则取消当前请求，禁止播放。

现有 `/v1` 接口保持兼容。Android 配置网关后默认 v2，`MODEL_GATEWAY_PROTOCOL=v1` 可回退；iOS 当前自动使用 v1 文件播放，未实现或验证 iOS 原生 PCM 播放。离线模拟聊天、SQLite v1 表结构、录音松开试听均保留。ASR 仍是占位，电话仍是交互演示。本次不增加人物动作接口。

## 连接和命令

`WebSocket /v2/conversations/{conversation_id}/stream`

开发阶段 conversation_id 仅支持 `local-xing`、`local-yue`。握手 `Authorization: Bearer <开发网关令牌>`，不是供应商密钥。生产部署前必须另做用户认证、会话授权、TLS 和配额隔离。

App 每次仅保持当前角色的连接，切换角色会关闭旧连接。连接成功返回 `session.ready`（`protocol=2`）。所有事件含 `event`、`request_id`、`character_id`，会话事件 request_id 为空。

| 命令 | 必需字段 | 语义 |
| --- | --- | --- |
| `chat.send` | request_id、character_id、content | 可选 history（默认空）、speech.enabled（默认 true）；一个请求同时安排文字和声音 |
| `turn.cancel` | request_id | 取消进行中的回复及声音；已经完成的文字保留 |
| `speech.cancel` | request_id | 仅停止声音；文字尚未完成时，禁止随后自动合成 |
| `speech.retry` | request_id、speech_id | 明确重试已经完成的回复的声音，不调用 DeepSeek |
| `turn.status` | request_id | 查询状态，重连后不自动重发生成请求、不自动播放历史音频 |

request_id / speech_id：16–100 位 ASCII 字母、数字、下划线或横线。首次 speech_id 由服务器生成；重试由客户端提供新 ID。character_id 必须与路径角色相同。content 1–2000 字，history 最多 20 项、总计 24000 字，每项 role=user/assistant、content 1–6000 字。输出最多 6000 字。chat.send 不接受未知字段。

同一 request_id、相同参数只返回状态，不再调用模型；参数不同返回 REQUEST_ID_CONFLICT。相同 speech_id 已完成时，仅在明确 speech.retry 后重放缓存，不重复计费；同 ID 已失败返回原失败，新一次供应商尝试要用新 ID。客户端当前使用新 ID 重试，不自动循环重试。

## 事件和音频格式

| 事件 | 关键字段 |
| --- | --- |
| `message.started` | 请求已开始 |
| `message.delta` | delta：可用于文字预览，不能作为完成或朗读依据 |
| `message.completed` | content：完整回复；speech_id：随后声音任务，无声音时为空 |
| `message.failed` / `message.cancelled` | code；不完整文字不朗读 |
| `audio.started` | speech_id、format=pcm_s16le、sample_rate=24000、channels=1、连接指标 |
| `audio.chunk` | **二进制帧**，见下文 |
| `audio.completed` | speech_id、bytes、chunks、连接及首包指标；表示合成传输完成，不表示设备已播放完 |
| `audio.failed` / `audio.cancelled` | speech_id、code；文字不回滚 |
| `turn.status` | status、content、code、speech_id、speech_status、speech_code |
| `cancel.accepted` | scope；取消命令受理，不保证上游已产生的费用能撤销 |
| `request.failed` | code；鉴权失败则拒绝握手 |

每个音频二进制帧为：4 字节无符号大端 JSON 头长度 + UTF-8 JSON 头 + 原始 PCM。头含 event=audio.chunk、request_id、character_id、speech_id、seq（从 0 递增）、offset（此前累计 PCM 字节）。PCM 为有符号 16 位小端、单声道、24000Hz，**不是 WAV/MP3，无文件头**。服务端每块最多 9600 字节，客户端检查 ID、顺序、偏移、格式和最终总量，错误即停止播放，禁止拼接到下一条声音。

示例命令：

```json
{"command":"chat.send","request_id":"demo-request-00001","character_id":"xing","content":"你好","history":[],"speech":{"enabled":true}}
```

## 生命周期与资源限制

- CosyVoice 同时一个活动任务。正常 task-finished 后连接可复用，闲置超过 45 秒后下次重建；错误、取消、协议不完整或连接故障立即丢弃。等待池锁最多 2 秒，忙返回 VOICE_BUSY。连接复用不省略 run-task/finish-task。
- DeepSeek HTTP keep-alive 池最多 4 连接，闲置 45 秒；App WebSocket 同一角色复用。重连仅允许重新建立传输，不自动重做收费任务。
- 模型回复最长 90 秒，合成最长 90 秒；上游单次收包最多 30 秒；下游单次发送最多 5 秒。服务最多 4 个并行文字请求，每条音频上限 12 MiB。
- 开发服务器独立 `streaming.sqlite` 保存请求状态、完整回复及用于明确重放的 PCM；不修改手机聊天数据库。保留 24 小时，在申请新记录时清理过期终态记录。turns+voices 合计上限 200 条，已缓存 PCM 达 128 MiB 时拒绝新任务（单次在途结果可能再占最多 12 MiB）。这不是长期聊天档案。
- 进程启动把遗留 running 记为 SERVER_RESTARTED；断线取消该连接的在途任务，已完成文字仍可查询。手机已有消息恢复不依赖服务器缓存。
- App 未保存文字时先缓冲声音，最多 12 MiB；保存失败取消声音。角色切换、后台、通话、录音、停止朗读都会使旧播放失效。重启 App 只恢复本地聊天，不自动重播声音。

## 延迟口径

2026-11-16 兼容扩展：角色应用已保存复刻音色时，`audio.started` / `audio.completed` 可包含 `voice_profile_id`。聊天请求不需要新增参数；同 speech_id 的缓存仍重放原音频，主动重试的新 speech_id 使用当前角色选择。详见[录音复刻与绑定契约](recording-voice-profiles-v0.md)。

连接指标 `reused`、`connection_serial`、`connection_setup_ms`、`first_packet_ms` 来自服务端单调时钟。first_packet_ms 从声音任务开始算起，包含排队/连接建立；不是用户已经听见。

Android 以 AudioTrack 时间戳（不可得时用 playback head 估算）定位第一个幅值超过 200 的 PCM 样本。App `ttsToOutputMs` 从收到完整文字到该样本的设备输出位置；`sendToOutputMs` 从 ChatController 接受发送开始，包含初始本地保存、连接和主模型等待。`underruns` 记录设备缓冲不足次数，并拆分 beforeDrain / duringDrain。Dart 与原生开始时刻通过方法通道近似对齐，非声学回录；指标不包含 Windows/远程桌面输出链路到人耳的延迟，也不能单凭零 underrun 断言无电音。

验收目标：热连接文字完成到设备出声 P50≤1.5 秒、P95≤2.5 秒；未达标如实记录。测试台词、首轮冷连接、后续实际 reused 样本和失败样本分别统计。真实聊天与固定台词测试分别列出，后者不调用 DeepSeek。
