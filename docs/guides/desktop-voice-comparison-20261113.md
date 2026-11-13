# 电脑端三模型声音对比

> 状态：评审中
> 日期：2026-11-13
> 负责人：待团队分配
> 关联：D、方案 PR #18、验证 PR #19

## 本轮范围

对比 CosyVoice 3.5 Plus、Flash 与本地 Qwen3-TTS 1.7B CustomVoice。目标为一个角色的平静、开心、安慰、疑惑四种表达。手机和真实对话大模型暂不接入。

Qwen 使用固定预设 Serena 直接生成最终台词。用同一预设生成一段中性参考，分别创建 Plus、Flash 的复刻音色；每个模型内部四种表达使用同一个音色，只调整表达指令。此设计比较本角色的实际使用效果，不等于三种模型使用完全相同的声音表示：Qwen 是预设，云端是从其合成录音复刻。不能据此推断所有真人音色上的模型排名。

原来 Qwen → 四段参考 → ZipVoice 的结果保留为历史实验，不再作为新路线的最终发声环节。公开真人语料的权利和标签问题记录在原验证报告；本轮参考是合成音频，不上传私人录音。

## 需要用户准备

1. 登录 [阿里云百炼](https://bailian.console.aliyun.com/)，选择 **华北 2（北京）**。首次使用按页面提示完成服务开通及账号要求。
2. 创建该地域、该业务空间的 **百炼 API Key**。需要语音合成 `cosyvoice-v3.5-plus`、`cosyvoice-v3.5-flash` 和音色复刻能力的调用权限。已有空间管理员限制模型访问时，请由管理员开放这两款模型及音色服务。
3. 取得该 Key 对应的 **业务空间 ID（Workspace ID）**，在业务空间管理/详情中查看；它不是账号 UID、AccessKey ID 或应用 App ID。
4. 确认有免费额度或可用余额。无需购买 GPU 服务器、OSS 存储、智能语音交互 ISI 的独立语音包，也无需准备 MiniMax 或 Qwen 云 API Key。

官方入口：[获取 API Key](https://help.aliyun.com/zh/model-studio/get-api-key)、[声音复刻](https://help.aliyun.com/zh/model-studio/voice-cloning-user-guide)。同一个北京区 Key 和业务空间可用于两款 CosyVoice 模型；音色 ID 按目标模型分别创建，不能跨型号混用。

在本机 PowerShell 运行，按提示输入 ID 和 Key：

```powershell
& 'D:\codex\erciyuan_AI\.worktrees\d-voice-desktop\experiments\voice_poc\configure_cloud.ps1'
```

脚本通过隐藏输入获取 Key，用 Windows DPAPI 加密保存到被 Git 忽略的 `.voice-local/dashscope-key.dpapi`。只有当前 Windows 账号/机器可解密。业务空间 ID 保存在同目录配置文件中。脚本不会发起 API 调用。不要把 Key 放进聊天、命令行参数、截图或仓库。

只检查是否配置，不显示内容：

```powershell
./experiments/voice_poc/configure_cloud.ps1 -Status
```

## 费用与依赖

本轮 32 条台词共 880 个计费字符（汉字按 2 个字符，标点按 1 个字符）。按 2026-11-13 北京区原价，Plus 一轮约 0.132 元，Flash 一轮约 0.0704 元；两款各跑三轮合计约 0.6072 元，未扣免费额度。CosyVoice 创建复刻音色免费。额外文本与重跑按实际字符另计。[官方价格](https://help.aliyun.com/zh/model-studio/model-pricing)

`--max-cost-cny` 默认为每次运行 2 元，在请求前按文本数量及固定价格快照估算，超过则不调用；遇到错误停下，不自动重试。它不是云账号的硬预算限制，价格变化和其他程序的消费不受该参数控制。建议本轮额外试验总预算控制在 10 元内，并在云控制台检查账单。

从仓库根目录运行。云端入口可在独立 Python 3.12 环境安装：

```powershell
python -m venv .voice-local/compare-venv
& .voice-local/compare-venv/Scripts/python.exe -m pip install -r experiments/voice_poc/requirements-comparison.txt
```

Qwen 另需本地权重和 `qwen-tts==0.1.1`，其依赖包括 `transformers==4.57.3`。本机已有 `.voice-local/cpu-venv` 的 Qwen 依赖，以及 `.voice-local/ref-venv` 的 PyTorch 2.5.1 / torchaudio 2.5.1 CUDA 12.1。`-CudaOverlay` 显式使用这套现有组合，先加载 CUDA 包，再加载 Qwen 依赖；不会安装或修改显卡驱动。其他机器可使用单独安装完成的 CUDA + Qwen 环境，以 `-Python` 指定，无需此开关。当前 Qwen 包没有真正的流式音频返回，`non_streaming_mode=False` 也不能将此接口变成流式生成。

## 执行

先制作一段中性参考（同一输出目录不能重复使用）：

```powershell
./experiments/voice_poc/invoke_comparison.ps1 -CudaOverlay reference --output .voice-local/comparison-reference
```

参考应为清晰的 10–20 秒语音；脚本允许 10–30 秒。本轮中性参考已做自动转写核对，音色与自然度随盲听一起审阅。用同一文件创建两款模型的音色，输入以 Base64 通过 HTTPS 提交，无需把录音放到公开下载地址：

```powershell
./experiments/voice_poc/invoke_comparison.ps1 -Cloud enroll --reference .voice-local/comparison-reference/reference.wav --output .voice-local/comparison-voices.json
```

每创建一个音色立即保存 ID，后续重跑查询已有 ID，避免重复创建。更换参考或业务空间时须使用新的 manifest 路径。已创建但仍部署中的音色可以稍后重新查询。音色 ID、参考、测试输出均不提交 Git。

检查播放设备，再运行。默认使用系统默认输出，可通过 `--audio-device` 指定设备编号；有远程音频重定向时须注明。

```powershell
./experiments/voice_poc/invoke_comparison.ps1 devices
./experiments/voice_poc/invoke_comparison.ps1 -CudaOverlay run --backend qwen --play --output .voice-local/comparison-qwen
./experiments/voice_poc/invoke_comparison.ps1 -Cloud run --backend plus --play --output .voice-local/comparison-plus
./experiments/voice_poc/invoke_comparison.ps1 -Cloud run --backend flash --play --output .voice-local/comparison-flash
```

上述封装默认使用本机已有 `cpu-venv`。云端使用新建的轻量环境时，在子命令前加 `-Python .voice-local/compare-venv/Scripts/python.exe`。Key 只在子进程环境中可用，退出后还原原环境。所有输出必须使用新目录，失败的部分结果保留供排查。

默认一轮为 8 句同文台词 × 4 表达，顺序随机且固定种子。第一轮确认听感后再用 `--repeats 3` 做延迟复测。新目录、新连接的首次请求单独报告；同连接后续请求和本地模型加载后的请求单独汇总。避免同时运行其他 GPU 任务。

生成不含模型/情绪标签的盲听目录：

```powershell
./experiments/voice_poc/invoke_comparison.ps1 package --runs .voice-local/comparison-qwen .voice-local/comparison-plus .voice-local/comparison-flash --reference .voice-local/comparison-reference/reference.wav --output .voice-local/comparison-blind
```

浏览器打开 `index.html`，在 `scores.csv` 中记录自然度、与固定角色参考的一致性（均为 1–5 分），以及听出的表达。答案单独保存在盲听目录的上一级。缺少云端结果时只传已完成目录，并明确这是单模型材料，不能据此做三模型排名。

## 测量与验收口径

| 字段/评价 | 含义与边界 |
| --- | --- |
| `first_audio_seconds` | 从本次 TTS 调用开始到第一段 PCM 到达。首次云端请求包含建连；本地 Qwen 当前接口到整段返回才得到 PCM。 |
| `generation_seconds` | 从 TTS 调用到完成，不能与流式首包混用。 |
| `first_non_silent_dac_estimate_seconds` | 根据播放设备 DAC 时间戳及首个超过阈值的 PCM 样本估算。缓冲 120ms 后启动；不等于实体扬声器或远程用户耳边的实测出声。 |
| `acoustic_first_sound_seconds` | 当前为空；需音频回环/外部采集或真机测量补充。 |
| `playback_starved_seconds` | 播放开始后，数据不足被填零的累计时长；同时记录 PortAudio underflow。 |
| 完整聊天延迟 | 本轮没有真实 LLM、ASR、说话结束判定，不能套用上一轮提出的 1.5–3.5 秒整链路目标宣布通过。 |

每轮输出 WAV、`experiment.json`、`runs.jsonl` 和 `summary.json`。P50/P95 使用最近秩法，报告样本量；32 条样本只作初筛，不作为上线延迟保证。失败记录不混入成功延迟，失败数保留。设备流在每条请求前创建，设备初始化和模型加载单独于热请求口径，不包含应用启动时间。

人工验收建议至少 3 名听者：自然度与音色一致性中位数均 ≥4/5；四表达听辨率目标 ≥75%，同时单独检查容易混淆的安慰/平静、疑惑/平静。连续切换语气不能明显换人。以上是待验证目标，合成成功或自动转写通过都不能代替人耳验收。

本轮完成的是实际 TTS 调用与播放记录。语音打断、弱网、多人并发、完整对话和手机实际出声仍属于后续验证，不标为已通过。

## 离线检查

```powershell
& .voice-local/cpu-venv/Scripts/python.exe -m unittest discover -s experiments/voice_poc -p test_comparison.py -v
```

测试覆盖调用前预算检查、凭据日志处理、任务确认后发文本、错误停机、连接复用及 PCM 分片边界；使用假 WebSocket，不调用付费服务。云端真实验证状态以报告为准。

协议依据：[客户端事件](https://help.aliyun.com/zh/model-studio/cosyvoice-client-events)、[服务端事件](https://help.aliyun.com/zh/model-studio/cosyvoice-server-events)、[音色 HTTP API](https://help.aliyun.com/zh/model-studio/voice-clone-design-http-api)。
