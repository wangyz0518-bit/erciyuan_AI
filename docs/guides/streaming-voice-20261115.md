# 服务器统一调度与 Android 流式语音验证

> 状态：待评审，禁止据此视为 iOS/真机验收
> 更新：2026-11-15
> 分支：codex/server-orchestrated-streaming-voice，基于 PR #21

先按[模型网关指南](model-gateway-20261115.md)配置本机服务与开发令牌。密钥保留在服务器环境中，不写入 App 或 Git。本轮接口见 [v2 契约](../接口/model-gateway-stream-v2.md)。

## 启动正式聊天链路

```powershell
# 仓库根目录，服务持续运行
pwsh -File services/model_gateway/run.ps1 -Mode live -Port 8787
# 另一个终端
D:\dev\android-sdk\platform-tools\adb.exe -s emulator-5556 reverse tcp:8787 tcp:8787
pwsh -File apps/mobile_poc/tool/windows.ps1 -Action run -Device emulator-5556 -GatewayConfig D:\codex\erciyuan_AI\.model-local\mobile-live.json
```

Android 默认使用 v2。如果只需复核旧接口，在本机 JSON 配置中增加 `MODEL_GATEWAY_PROTOCOL: "v1"` 后重新构建；不能仅热重载。iOS 自动走 v1 文件朗读，边生成边播放需要同伴实现 iOS PCM 适配后另行验收。

## 自动检查

```powershell
# services/model_gateway 下
D:\dev\model-gateway-venv\Scripts\python.exe -m pytest -q
# 仓库根目录下
pwsh -File apps/mobile_poc/tool/windows.ps1 -Action analyze
pwsh -File apps/mobile_poc/tool/windows.ps1 -Action test
pwsh -File apps/mobile_poc/tool/windows.ps1 -Action stream-fault -Device emulator-5556
pwsh -File apps/mobile_poc/tool/windows.ps1 -Action stream-regression -Device emulator-5556 -GatewayConfig D:\codex\erciyuan_AI\.model-local\mobile-live.json
pwsh -File apps/mobile_poc/tool/windows.ps1 -Action stream-live -Device emulator-5556 -GatewayConfig D:\codex\erciyuan_AI\.model-local\mobile-live.json
```

stream-fault 在设备内启动替身 WebSocket，使用真实 SQLite 和 AudioTrack，注入语音失败、格式错误和最终写盘失败，不调用供应商。stream-regression 聚合原有离线能力、存储失败、网关及新流式故障测试，不开启麦克风；其网关用例会真实调用一次模型（也可另启 mock 服务传 mobile-mock.json）。stream-live 使用合成测试对话，在两角色各聊五轮，会真实调用 DeepSeek/CosyVoice；真实调用日志只留本机。原 suite 含麦克风录音，需另行安排，本轮未运行。

## 固定 24 条台词的冷/热对比

独立测试服务器只返回预置台词，不持有 DeepSeek 密钥。重置连接控制端点仅存在于 tests/benchmark_server.py；正式网关没有这些端点。各轮统一 calm、语速 1.0；沿用早先 24 个台词编号，但不比较早先不同语气/语速的效果。

```powershell
# 仓库根目录；此脚本使用现有 Windows DPAPI 语音配置
pwsh -File services/model_gateway/tests/run_benchmark.ps1 -Manifest D:\codex\erciyuan_AI\services\model_gateway\tests\fixtures\voice-lines.json
# 另一个终端
D:\dev\android-sdk\platform-tools\adb.exe -s emulator-5556 reverse tcp:8789 tcp:8789
pwsh -File apps/mobile_poc/tool/windows.ps1 -Action stream-benchmark -Device emulator-5556 -GatewayConfig D:\codex\erciyuan_AI\.model-local\mobile-benchmark.json
```

先 24 次冷连接（每次关闭供应商连接再生成），再连续 24 次（第 1 次仍冷、余下按实际 reused 分类）。测试走完整服务器/手机保存文字/PCM 播放链路。每行 STREAM_BENCHMARK 输出样本编号与指标，不输出密钥或测试文本。测试期间不要手动操作模拟器，也不要并行运行其他设备测试。

原始音频和完整设备日志只留 `.model-local/` 或本机证据目录。提交报告只保留脱敏统计。首次设备出声指标是 Android 音频时间戳，不是麦克风回录或人耳听到的实测时刻。underruns 原始值与 beforeDrain / duringDrain 分开看：播完后的排空可能增加计数，不能把它直接当作中途断续，也不能抹掉它。电音、断词、变速必须另作人工试听。

`tests/summarize_streaming.py --benchmark <日志> --live <日志> --out <JSON>` 只提取白名单指标，不复制聊天内容、供应商标识或令牌。本轮报告的固定台词日志早于总延迟时钟修正，提取时另加 `--benchmark-command-clock`；其“文字完成至出声”口径不变。新跑的测试不用该标志。

## 本轮实现边界

- Android 原生播放器接受 24kHz/16bit/mono PCM，预缓冲 400ms、后台写入，不把 PCM 当 WAV 播放。先收到音频结束事件，再等设备排空。
- 已保存的文字与声音失败互不回滚；重试声音不重问 DeepSeek。切换角色、停止、录音、页面离开均取消旧声音。
- 音频只临时缓冲；手机 SQLite 数据结构未变。服务器开发缓存按 v2 契约有限保留，不作为手机聊天恢复的唯一来源。
- 断开连接后不会自动补发收费请求或自动重播旧声音。开发者可通过 turn.status 查询服务器结果；目前 UI 不提供断线后的服务器记录导入，手机仍按原有失败/取消记录恢复与手动重试。
- PR #13、#15、#16、#21 及本任务 PR 均不因本轮工作而合并。
