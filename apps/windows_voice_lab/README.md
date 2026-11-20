# Windows 声音测试台

Python 3.12 / Tkinter / sounddevice；直接复用本机模型网关。DeepSeek 完整文字后由服务器调用 CosyVoice，客户端流式播放 PCM，可停止和明确重试。独立 SQLite 保存角色聊天记录。

安装 `requirements-lock.txt`，从仓库根目录运行 `./apps/windows_voice_lab/run.ps1`。模型密钥由网关持有，客户端只读取本机网关地址与令牌，不要求输入供应商密钥。

- [录音上传、复刻、试听、应用角色及验收命令](../../docs/guides/recording-voice-cloning-20261116.md)
- [音色接口与保存规则](../../docs/接口/recording-voice-profiles-v0.md)
- [本轮真实验证与未验证项](../../docs/reports/recording-voice-cloning-20261116.md)

测试：`python -m unittest discover -s tests -v`。`clone_acceptance.py` 是显式启动的真实付费测试，会播放声音、应用音色到小星；不会读日常聊天库。不要与手动聊天并发运行。
