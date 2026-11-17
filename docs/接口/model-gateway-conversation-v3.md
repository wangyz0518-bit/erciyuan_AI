# 连续语音会话 v3

> 状态：评审中，Windows 验证实现；尚未接入手机
> 日期：2026-11-18
> 负责人：待定
> 关联：A/B/D、流式 v2、录音音色 v0

## 范围

三种输入共用同一角色上下文：文字、按住说话松开发送、连续通话。
Python/FastAPI 调度 DeepSeek、Qwen 实时 ASR、CosyVoice v3.5 Flash。
本轮仍在完整回答保存后合成语音；按短句提前合成属于后续优化。
v1/v2、旧 Windows 测试台和手机数据库保持兼容。v3 另存本机数据库，不代表历史数据已迁移。

## 连接与鉴权

`WebSocket /v3/conversations/{character}/stream`，角色为 `xing` 或 `yue`。
建立后 5 秒内发送 `{"command":"session.start","token":"<本机开发令牌>"}`。
浏览器令牌不放查询参数；启动器用 URL fragment 交给页面，页面随即移除 fragment，不持久保存令牌。
若有 Origin，须为与 Host 相同的 loopback 来源。整个 v3 服务同时只接纳一个客户端会话，冲突为 `SESSION_BUSY`。
仅供单用户本机开发，必须绑定 loopback；生产身份、TLS、配额与多租户授权不在本协议范围。

成功返回 `session.ready`：`protocol=3, session_id, character_id, mode, history`。
后续事件携带 `session_id`；上游输出携带 `reply_id`，识别事件携带 `input_id`。
客户端只接受当前会话、当前输入/输出的事件，已取消 ID 的迟到结果不得恢复播放。

## 命令

| command | 字段 | 语义 |
| --- | --- | --- |
| chat.send | request_id, text, speak（默认 true） | 文字输入；默认生成语音，false 只返回文字 |
| input.start | input_id, kind=hold/call | 开始一段语音；输入与旧输出生命周期独立 |
| input.commit | input_id | 一段音频发送完毕，确认 ASR 最终结果后才调用主模型 |
| input.abort | input_id | 放弃该段；若已转成回复则取消同 ID 回复，不影响较新任务 |
| turn.interrupt | reply_id | 停止该回复及合成，重复/过期取消返回 stale=true |
| playback.progress | reply_id, frames, complete（默认 false） | 播放位置估计；不是人耳听到的证明 |
| session.ping | 无 | 返回 session.pong；客户端每 30 秒保活 |
| session.end | 无 | 取消输入/输出、释放会话占用后关闭连接 |

后续命令拒绝未知字段。ID 为 16–100 位 ASCII 字母、数字、下划线或连字符。
文字去首尾空白后 1–2000 字。相同文字请求 ID 与相同内容、角色、朗读开关仅返回 `turn.status`，不重新计费；不同参数返回 `REQUEST_ID_CONFLICT`。
输入 ID 不可重复使用；连接中最多 2000 个输入 ID。失败不自动调用供应商重试。

## 音频

二进制格式：4 字节大端 JSON 头长度 + UTF-8 JSON 头 + PCM。

- 上行头 `{input_id, seq}`，seq 从 0 递增。PCM16 小端、单声道、16 kHz，每块 2–6400 字节且偶数，单段最多 30 秒；有效录音至少 200 ms。
- 为覆盖冷建连，输入队列最多 1024 块，总 PCM 仍受 960000 字节限制。序号错误、超长、队列满立即取消本段，并带 input_id 报错。
- 下行头 `{event:"audio.chunk", session_id, reply_id, seq, offset}`，PCM16 小端、单声道、24 kHz。offset 是此前 PCM 字节数。
- `audio.started` 给出格式和角色音色；`audio.completed` 给出 total_frames/chunks/metrics，仅表示合成传输完成。
- 客户端校验序号、offset、最终长度；缓冲最多 60 秒 PCM。异常或打断立即清空，不拼接到下一轮。
- progress 不得超过服务端已生成帧数；仅完整传输且 complete=true、frames=total_frames 才标记 played。

## 事件和持久化

识别事件：`input.ready`、`transcript.partial`、`transcript.final`、`input.aborted`、`input.failed`。
partial 只供字幕，禁止保存为已发送用户消息或触发主模型。

回复事件：`turn.saved`（完整用户消息）、`reply.delta`（回复预览）、`reply.saved`（完整文字已落盘）、音频事件、`turn.completed`、`turn.failed`。
服务器先保存完整回复再开始音频。文字成功而语音失败时保留文字。
取消受理返回 `interrupt.accepted`；不能撤销此前已发生的供应商费用。
`request.failed` 给出固定 code，以及可安全验证的 input_id/request_id/reply_id，方便客户端取消匹配操作。

`GET /v3/conversations/{character}` 返回最近 100 轮；`GET /v3/recordings/{id}` 返回 hold 原录音的 16 kHz WAV。均需 Bearer 开发令牌。
本机 `conversations-v3.sqlite` 保存角色、输入方式、用户文字、回复、状态、播放估计和 hold 音频。
call 原音频不落盘；语音识别及回复会发送给配置的云端供应商，不承诺供应商不留存数据。
容量 2000 轮/128 MiB 原录音，达到上限报错，不静默删除。尚未提供归档/删除 UI。
模型上下文最多 20 条消息、24000 字，各角色隔离。通话若未确认完整播放，使用“上轮被打断/未确认播完”提示，不假装用户听完全部内容；暂未实现逐字播放对齐。
断线/结束取消在途任务，重启把遗留任务标记中断；恢复历史不重发、不重播。

## 客户端控制

客户端负责回声消除、人声检测和停播，服务器不承担本地实时停播。
当前 Windows 使用浏览器请求 AEC/降噪、Silero VAD v5：有效人声门限 160 ms、结束等待 800 ms、预留前音 320 ms。这些是待真人校准的初始参数。
疑似人声先暂停播报，确认有效人声再取消旧回复；误触发则放弃该输入并恢复播报。
录音松开提交、上滑取消；连续通话自动提交；静音停止麦克风，挂断/换角色/隐藏页面结束采集。
音色沿用 v0 绑定；在 v3 占用期间拒绝修改绑定，网页主动释放会话后修改，再连接。

## 参考

- [Qwen 实时 ASR 交互](https://help.aliyun.com/zh/model-studio/qwen-asr-realtime-interaction-process)：使用 Manual 断句，turn_detection=null。
- [VAD 浏览器 API](https://docs.vad.ricky0123.com/user-guide/api/)：实现以固定安装的 0.0.30 包为准。
- [Windows 操作和验收](../guides/windows-conversation-20261118.md)。
