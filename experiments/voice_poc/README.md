# D 工作线电脑语音验证

> 状态：评审中
> 日期：2026-11-13
> 负责人：待团队分配
> 关联：D、方案 PR #18

本目录提供 Windows CPU 上的 ZipVoice 四表达筛选入口。参考录音、权重、试听音频和逐条日志位于仓库根目录的 `.voice-local/`。实验结果见 [电脑验证记录](../../docs/reports/desktop-voice-screening-20261113.md)。

从仓库根目录运行以下 PowerShell 命令。需要 Python 3.12 和 Windows 自带的 `curl.exe`、`tar.exe`。

```powershell
New-Item -ItemType Directory -Force .voice-local | Out-Null
python -m venv .voice-local/venv
$voicePython = '.voice-local/venv/Scripts/python.exe'
$env:PIP_CACHE_DIR = Join-Path $PWD '.voice-local/pip-cache'
& $voicePython -m pip install -r experiments/voice_poc/requirements.txt

$voiceModel = 'sherpa-onnx-zipvoice-distill-int8-zh-en-emilia'
curl.exe -fLsS -o ".voice-local/$voiceModel.tar.bz2" "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$voiceModel.tar.bz2"
curl.exe -fLsS -o .voice-local/vocos_24khz.onnx https://github.com/k2-fsa/sherpa-onnx/releases/download/vocoder-models/vocos_24khz.onnx
$voiceDataset = 'https://huggingface.co/datasets/ATH-MaaS/CSEMOTIONS/resolve/19498e62e6745cf9ec9b69a44b826caa467eac31'
curl.exe -fLsS -o .voice-local/csemotions-first.parquet "$voiceDataset/data/train-00000-of-00008.parquet"
```

对照验证记录的 SHA-256 校验下载，再运行本地合成。每次为输出指定新目录，保留原来的运行记录。

```powershell
tar.exe -xf ".voice-local/$voiceModel.tar.bz2" -C .voice-local
& $voicePython experiments/voice_poc/prepare_csemotions.py --parquet .voice-local/csemotions-first.parquet --output .voice-local/cse-references
& $voicePython experiments/voice_poc/run_zipvoice.py --model-dir ".voice-local/$voiceModel" --vocoder .voice-local/vocos_24khz.onnx --references .voice-local/cse-references/references.json --cases experiments/voice_poc/screening-cases.csv --output .voice-local/first-screening
```

输出是随机顺序的编号 WAV、逐条记录 `runs.jsonl` 和汇总 `summary.json`。盲听时只提供音频和台词，标签保留在逐条记录中。`--order-seed` 固定试验顺序，模型自身的采样仍可能使两次生成有差异。耗时从调用模型到完整音频返回，包含参考音频预处理，播放延迟需另测。

## 使用合成参考

用 [Qwen3-TTS 1.7B CustomVoice](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice/tree/0c0e3051f131929182e2c023b9537f8b1c68adfe) 在本机制作同一预设 Serena 的四段参考。把固定版本的模型文件保存到 `.voice-local/qwen-customvoice/`，包括 `speech_tokenizer/` 子目录。使用独立 Python 3.12 环境安装 `qwen-tts==0.1.1`、`torch` 和匹配版本的 `torchaudio`。本轮制作环境使用 PyTorch 2.5.1 CUDA 12.1 与 RTX 4060 Laptop。

```powershell
$env:HF_HUB_OFFLINE = '1'
$env:TRANSFORMERS_OFFLINE = '1'
& $qwenPython experiments/voice_poc/make_synthetic_references.py --model-dir .voice-local/qwen-customvoice --output .voice-local/synthetic-refs --device cuda:0 --normal-speed-comfort
```

`$qwenPython` 指向独立环境的 Python。生成后用 `.voice-local/synthetic-refs/references.json` 替换上面的 `--references` 路径，使用新的输出目录再运行 ZipVoice。两套引擎之间传递四段 WAV 和对应文字。
