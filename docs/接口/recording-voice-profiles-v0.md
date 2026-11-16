# 录音复刻音色与角色绑定 v0

> 状态：评审中（项目发起人已确认本轮实现范围）
> 日期：2026-11-16
> 负责人：待定
> 关联：D 声音、Windows 测试台、模型网关 v0 / 流式 v2

## 范围与兼容

本机单用户开发服务：上传已有录音 → CosyVoice v3.5 Flash 复刻 → 新台词试听 → 自动保存音色列表 → 明确应用到角色。没有文字描述、混合微调或录音转文字功能。预览文字是朗读台词，不是音色描述。

复用现有网关令牌鉴权，所有下列接口都需要 `Authorization: Bearer <本机网关令牌>`。供应商密钥和云端 voice_id 只留在服务端。不能把本接口直接暴露给公网或多用户；生产需要用户身份与资源归属控制。

现有手机消息表、Windows `turns` 表以及 v1/v2 聊天请求字段不变。v2 `audio.started` / `audio.completed` 可额外包含 `voice_profile_id`（本系统 ID，可忽略），无需客户端传入供应商 ID。服务器在开始一个新合成任务时读取角色绑定并保存选择快照；进行中的聊天或声音任务拒绝修改绑定。

## 接口

| 方法与路径 | 请求 | 返回 / 作用 |
| --- | --- | --- |
| POST `/v1/voice-profiles` | multipart：`request_id`、`name`、`consent=true`、`file` | 202，创建任务；同内容可返回原任务并带 `duplicate=true` |
| GET `/v1/voice-profiles` | 无 | `{items: [...]}`，当前供应商配置范围内的音色 |
| GET `/v1/voice-jobs/{id}` | 无 | 任务状态；未知创建结果只做只读核实 |
| POST `/v1/voice-jobs/{id}/cancel` | 无 | 取消等待或试听任务；不能撤销已提交到云端的创建 |
| POST `/v1/voice-jobs/{id}/retry` | `{request_id}` | 202，明确失败后的新尝试；结果未知的创建禁止重发 |
| POST `/v1/voice-profiles/{id}/previews` | `{request_id, text}` | 202，生成完整 WAV 试听，不调用 DeepSeek |
| GET `/v1/voice-jobs/{id}/audio` | 无 | `audio/wav`、`Cache-Control: no-store`；需鉴权 |
| GET `/v1/characters/{character}/voice-binding` | 无 | `{character_id, profile_id, revision, name}` |
| PUT `/v1/characters/{character}/voice-binding` | `{profile_id, revision}` | 保存选择；`profile_id=null` 恢复默认，revision 必须与读取值一致 |

`character` 仅为 `xing` / `yue`。`request_id` 为 16–100 字符的字母、数字、下划线、连字符；名称去首尾空白后 1–40 字；试听台词 1–200 字、不能全空白。额外字段拒绝接收。创建接口只在 live 模式启用。

音色条目：`id, name, status, code, created, audio, last_job_id`。audio 包含标准化后时长、24000 Hz / 单声道、原采样率与 RMS。任务：`id, kind, status, code, created, profile_id, profile_status, audio_url`；audio_url 为空时不可播放。本扩展 `created` 使用 Unix 秒，区别于未实施完整 v1 草案的 ISO 时间；调用方不得把二者混用。

任务状态为 running / complete / failed / unknown / cancelled；音色状态为 processing / ready / failed / unknown。创建完成即可保存，应用角色是独立操作。

试听任务额外返回 `text`（该次生成的台词），重新选择音色/重开面板时同步恢复它，避免显示的文字与旧试听不一致。编辑台词后需要重新“生成试听”，“播放试听”始终播放上次生成的结果。

## 去重、取消和恢复

- 相同 request_id + 相同请求返回原任务；同 ID 改内容返回 409 `REQUEST_ID_CONFLICT`。
- 同一配置范围内相同原始文件 SHA-256 复用一个音色，即使换名称也不会重建或重命名。转码后的不同文件不按听感去重。
- 云端创建超时、连接中断、5xx 或返回缺失 ID：unknown。随后用已保存云端 ID 或唯一 prefix 查询，绝不自动重新创建。不能查明时保持待核实。
- 云端明确拒绝才允许用户点击重试。临时参考已过期返回 `REUPLOAD_REQUIRED`；重新上传同一原文件只补齐参考，再明确重试。
- 取消创建只取消等待；服务器仍收集迟到结果，可能出现“任务已取消、音色可用”。不会自动绑定，不代表云端音色已删除。
- 启动时未完成的创建改为 unknown 并允许查询；未完成试听改为 failed。关闭窗口、重开和恢复列表均不自动播放。
- 相同 speech_id 的完整聊天音频缓存始终重放原 PCM；用户主动重试朗读使用新的 speech_id 和当前角色声音。重试朗读不重新调用 DeepSeek。
- 自定义音色无法使用时返回失败，保留文字，不偷偷改用其他声音。恢复默认是用户明确操作。

## 音频与保存规则

- WAV / MP3 / M4A，非空、≤10 MiB、10–30 秒、原采样率≥16 kHz。真实语音清晰度仍需人工判断；这里只检测解码、时长、采样率与接近静音。
- FFmpeg 只允许本地 file / pipe、强制容器解码、最长处理 31 秒并拒绝超长，20 秒进程超时。取第一声道、重采样到 24 kHz / PCM16 单声道；不变调、不调速、不加情绪描述、不自动裁剪或去噪。
- 网关独立 `voice_profiles.sqlite`：音色元数据、云端 ID、任务、幂等别名、角色绑定和合成选择快照。用户原文件不移动、不改写。
- 上传临时文件校验后立即移除。标准化参考创建成功后立即移除；失败/待核实参考和生成试听 WAV 最长保留约 24 小时（每分钟清理，停服期间下次启动清理）。客户端只在内存播放试听。
- 合成选择快照在写入时清理 24 小时前条目；音色、绑定和任务元数据跨重启保留。本 PoC 每配置最多 50 音色、全库 1000 任务和 1000 去重别名，满额明确报错；尚未提供自动归档或音色删除。
- 恢复默认不会删除云端音色；本地清理文件也不代表供应商已删除云端音色。云端资源撤销/删除功能留后续。
- 所有上述数据库、原音频、试听、密钥和真实对话只留忽略目录，不提交 Git。密钥、模型、地域/业务空间改变后原音色不可误用，需重新核实配置。

## 常见错误

响应沿用 `{error: {code, message}}`，不回传供应商完整错误或上传内容。401 未鉴权；413 文件过大；422 无效录音/字段；404 不存在；409 状态冲突；410 试听过期；503 `VOICE_SAVE_FAILED` 保存失败。

重点区分 `VOICE_RESULT_UNKNOWN`（刷新核实）、`VOICE_CREATE_REJECTED`（明确失败）、`VOICE_BUSY`（稍后）、`BINDING_CHANGED`（刷新版本）、`VOICE_SCOPE_CHANGED`（配置变更）、`PREVIEW_EXPIRED`（重新生成）。SQLite 绑定写入失败时事务回滚，旧选择不变。
