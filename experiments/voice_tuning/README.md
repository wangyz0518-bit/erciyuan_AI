# 参考音色＋文字指令：独立验证

> 状态：实验，听感待确认
> 日期：2026-11-16
> 关联：D 声音能力；不改正式聊天接口

本实验复用已由参考音频创建的 `cosyvoice-v3.5-flash` 音色，在合成时传入文字 `instruction`。不是把音频和文字一起交给一个“修改音色”创建接口，也没有创建新的永久音色。无 DeepSeek 调用，无麦克风采集，无聊天网关依赖。

## 方法

- 同一参考与音色：先校验参考文件哈希及账号/空间指纹，再查询音色状态为 OK。
- 两条固定台词 × 两个 seed（42、43）× 六组：无指令、慢一点、更柔和、音调稍低、略带沙哑、rate=0.85 参数对照。
- 前五组的 rate/pitch 固定 1.0、volume 固定 50；不把直接调参数的结果算作文字指令效果。
- 同一台词同一轮使用相同 seed；固定随机顺序，复用供应商连接；每个样本仅调用一次，失败不自动重试。
- PCM 24 kHz / 16 bit / 单声道；检查有效非静音样本、时长、RMS、峰值、削波比例。active_span 是按 10ms 能量窗去掉首尾低能量后的跨度，含句中停顿，不是语音速度或音色相似度评分。
- `first_packet_s` 从发送 run-task 后等待开始计时，不含连接建立，也不是耳朵听到的时间。
- 中文指令按汉字 2、其他字符 1 加权，调用前检查不超过 100。本实验只用中文；不声称覆盖全部 Unicode 文字的计数规则。

## 运行

已有 Windows 测试环境：Python 3.12，numpy 2.5.4、websockets 15.0.1。`run.ps1` 只在子进程环境加载 DPAPI 保存的 DashScope Key，结束后恢复原值。可使用现有 HTTPS_PROXY，不修改系统设置。禁止把凭据写到命令行或日志。

`VoiceConfigRoot` 需要已有的 `comparison-voices.json`、`dashscope-config.json`、`dashscope-key.dpapi` 与 `comparison-reference/reference.wav`；这些是忽略目录内的机器配置，不随仓库交付。没有已复刻音色时，应先单独完成音色创建，不能伪造 manifest。

```powershell
./run.ps1 -VoiceConfigRoot <现有本机配置目录> -OutputDirectory <新的.model-local输出目录>
# 只补测指定条件，必须使用新的输出目录：
./run.ps1 -VoiceConfigRoot <现有本机配置目录> -OutputDirectory <新的输出目录> -Variants lower,husky
```

输出 `manifest.json`、逐样本 `results.json`、WAV 和 `listen.html`。双击 HTML 即可逐组试听；参考、原始输出及人工记录都留在本机。建议先听参考，再听同文基线，最后比较微调版；同时记录“仍像同一人／变化符合要求／是否自然／断字电音”。原始样本不做响度归一化，要注意响度差异可能影响主观判断。

可选离线文字核对使用已经安装 sherpa-onnx 和 soundfile 的 Python 环境：

```powershell
python check_words.py --directory <输出目录> --model <本机SenseVoice模型目录>
```

ASR 差异只用于定位疑似错字，不自动认定是 TTS 错字；转写正确也不能证明音色保持或听感自然。人工评价未返回时保留“待确认”。

结果与本轮指令修订记录见 [验收报告](../../docs/reports/voice-reference-tuning-20261116.md)。

## 官方依据

- [复刻音色接口](https://help.aliyun.com/zh/model-studio/voice-clone-design-http-api)
- [指令控制及 100 字符限制](https://help.aliyun.com/zh/model-studio/realtime-tts-user-guide)
- [合成参数与事件](https://help.aliyun.com/zh/model-studio/cosyvoice-client-events)
