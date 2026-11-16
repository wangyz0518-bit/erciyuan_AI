# Companion model gateway

Python 3.12 + FastAPI。DeepSeek 生成完整回复后，CosyVoice Flash 合成朗读音频；录音转文字返回明确的未实现状态。

`requirements.txt` 列出直接依赖，`requirements-lock.txt` 记录本轮 Python 3.12 验证环境的完整版本，用于复现。

- [启动、密钥配置及 Android/iOS 联调](../../docs/guides/model-gateway-20261115.md)
- [请求、事件、取消、重试与本机服务边界](../../docs/接口/model-gateway-v0.md)
- [实际验收结果](../../docs/reports/model-gateway-20261115.md)
- [v2 服务器统一调度协议](../../docs/接口/model-gateway-stream-v2.md) / [Android 流式验证指南](../../docs/guides/streaming-voice-20261115.md)
- [录音复刻与角色绑定](../../docs/接口/recording-voice-profiles-v0.md) / [Windows 操作与验收](../../docs/guides/recording-voice-cloning-20261116.md)

测试：`python -m pytest -q`。启动：`python -m uvicorn gateway.app:create_app --factory --host 127.0.0.1 --port 8787 --no-access-log`，先配置 `.env.example` 列出的环境变量（模板不会自动加载）。Windows 可用 `run.ps1`。不要使用多个 worker，也不要直接暴露到公网。
