# D 工作线电脑语音验证记录

> 状态：评审中
> 日期：2026-11-13
> 负责人：待团队分配
> 关联：D、[方案 PR #18](https://github.com/wangyz0518-bit/erciyuan_AI/pull/18)

## 参考样本

CSEMOTIONS 数据卡明确列出语音克隆和表达迁移用途。发布方 NOTICE 同时说明合集中有仅限研究的第三方 ESD，具体适用范围以来源和 NOTICE 为准。本轮取第一分片 `female001` 的四段录音，用于本机研究筛选，记录样本编号和原始标签。团队如要进一步分发声音，须先确认单条样本的权利范围。[数据卡](https://huggingface.co/datasets/ATH-MaaS/CSEMOTIONS) · [NOTICE](https://huggingface.co/datasets/ATH-MaaS/CSEMOTIONS/blob/main/NOTICE) · [ESD 原始说明](https://github.com/HLTSingapore/Emotional-Speech-Data)

| 目标表达 | 行号（从 0 开始） | 原始标签 | 截取范围 | 用法 |
| --- | ---: | --- | --- | --- |
| 平静 | 210 | neutral | 0.80–3.25 秒 | 中性陈述 |
| 开心 | 148 | happy | 0.92–3.08 秒 | 原始标注为开心 |
| 安慰 | 207 | neutral | 0.22–3.60 秒 | 从带鼓励内容的台词截取，待听辨 |
| 疑惑 | 196 | neutral | 0.22–2.50 秒 | 从问句截取，待听辨 |

数据堂列出同一语料库覆盖开心、安慰、困惑和中立，获取入口为申请样例或购买咨询。浙江大学 CEPD 明确覆盖中性、开心和困惑，页面标注仅供研究，情绪清单中无安慰。本轮采用上表样本用于初筛，四种表达的真人样本仍需补齐明确的标签或人工听辨。[数据堂语料页](https://www.datatang.com/dataset/1690) · [CEPD](https://zju-eclab.github.io/resources/cepd/)

## Windows 本地结果

Windows 11、i7-13620H、约 32 GB 内存。ZipVoice-Distill INT8、sherpa-onnx 1.13.8、Vocos 24 kHz，CPU 4 线程、4 步推理。每条台词使用本地参考和逐字稿，生成 24 kHz 单声道 WAV。[ZipVoice 部署说明](https://k2-fsa.github.io/sherpa/onnx/tts/zipvoice.html)

ZipVoice 模型卡将基于 Emilia 的预训练权重列为 CC BY-NC。本轮为本地非商业研究验证，商用部署须另选许可合适的权重或取得许可。解压后的推理模型、声码器和词典合计约 194.65 MiB。[ZipVoice 权重许可](https://huggingface.co/k2-fsa/ZipVoice#4-license)

| 轮次 | 参考长度 | 有效 WAV | 热运行生成 P50 / P95 | 本地 SenseVoice 转写差异 |
| --- | --- | ---: | --- | --- |
| 长参考初试 | 6.88、9.28 秒 | 8/8 | 2.70 / 3.53 秒（7 次） | 12/106 字，3 段有差异 |
| 短参考筛选 | 2.16–3.38 秒 | 32/32 | 0.93 / 1.16 秒（31 次） | 1/424 字，1 段有差异 |

短参考轮为 8 条新台词乘以 4 组参考，使用同一句台词做对照。模型加载 1.39 秒，首次生成 0.94 秒，生成耗时与音频时长的比值 RTF 中位数 0.33，最大 0.46。长参考轮同时更换了开心的参考台词，短参考轮增加了台词和表达数量。两组结果说明可用配置的实测差别，参考长度的独立影响需要匹配输入复测。

本地 SenseVoice 转写与 4 段截取参考的逐字稿一致。短参考轮编号 018 的“右手边了”被识别为“右手边吧”，待人工复核。生成用时止于模型返回完整波形。实际播放首声、正式字错率、断网用例及持续运行属于后续验收。[SenseVoice 本地模型](https://k2-fsa.github.io/sherpa/onnx/sense-voice/pretrained.html)

表达辨识度、自然度和音色一致性待人工试听。每种表达在相同台词中使用固定参考，音频按编号随机排列。局部试验支持继续桌面验证，正式验收状态为待验证。

## 用同一预设音色补齐四种表达

采用 Qwen3-TTS 1.7B CustomVoice 的 Serena，在 RTX 4060 Laptop 上为同一句台词生成四段参考。本轮用合成参考补足公开真人语料中的标签缺口。四段转写与参考台词一致，时长依次为 1.92、1.12、4.48、2.16 秒。[Qwen 官方模型卡](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice)

将四段参考送入 ZipVoice 生成同样的 32 段新台词，全部得到有效 WAV。热运行生成 P50 1.33 秒、P95 3.22 秒。安慰参考 4.48 秒时，该组输出时长中位数达到 6.01 秒，生成耗时中位数 2.83 秒。SenseVoice 转写有 5/424 字差异，涉及 3 段，需人工复核。

将安慰参考改为日常语速的 1.28 秒版本，保持另外三段参考，复跑 32/32 成功。热运行生成 P50 0.92 秒、P95 1.42 秒。安慰组输出时长中位数 1.99 秒、生成耗时中位数 0.88 秒。SenseVoice 转写有 3/424 字差异，涉及 3 段。参考变更同时影响语速和语气，表达保留程度待同文盲听。

另起 Python 进程拦截 Python socket 创建和域名查询，加载本地权重并合成 10 条新句，10/10 生成成功。系统网卡保持连接，系统级断网测试待做。

本机试听材料位于 `.voice-local/desktop-four-expressions.wav`，按平静、开心、安慰、疑惑的目标顺序拼接同一条新台词。盲听材料位于 `.voice-local/desktop-blind-listening/`，包含 32 条编号音频和评分表，答案在 `.voice-local/qwen-zipvoice-normal-speed/runs.jsonl`。

## 复现与校验

下载命令、依赖和入口见 [电脑验证说明](../../experiments/voice_poc/README.md)。

| 文件 | SHA-256 |
| --- | --- |
| ZipVoice-Distill INT8 发布归档 | `77219c8b40f4ee8d73a7f902305ff6c1128ef9b54461c41b4ca6ed890b6c2803` |
| `vocos_24khz.onnx` | `bcb3b970e384161c4d634f0bb9e999ff1c471b34c9bc0b1049a5014065ed3cc0` |
| CSEMOTIONS 第一分片，版本 `19498e62e6745cf9ec9b69a44b826caa467eac31` | `caeb0357cf4fc990204ec83d6c0692303fcde2997767a965b86ff4f489c3ce8e` |
| Qwen3-TTS CustomVoice `model.safetensors`，版本 `0c0e3051f131929182e2c023b9537f8b1c68adfe` | `38b1d5971bdbd982b561cccec982669a53b0537c3cf5e9bd4778ed07bb2f5137` |
| 同版本 Qwen `speech_tokenizer/model.safetensors` | `836b7b357f5ea43e889936a3709af68dfe3751881acefe4ecf0dbd30ba571258` |
