# Windows 连续聊天测试版

> 状态：评审中，真人麦克风、外放回声与听感待验收
> 日期：2026-11-18
> 关联：A/B/D、模型网关 v3

本机 Python 网关 + Edge/Chrome 网页，提供打字、按住说话和连续通话。
双击 `Launch.cmd`；入口与手动检查见[操作指南](../../docs/guides/windows-conversation-20261118.md)。
当前依赖此 Windows 工作站已有 Python 环境及本机供应商配置，尚非可分发安装包。

自动检查：仓库根目录执行 `node --test apps/windows_conversation_lab/tests/*.test.cjs`；网关目录执行 `python -m pytest -q`。
`live_smoke.py` 和 `live_interrupt_smoke.py` 是显式运行的真实付费测试，只用合成语音，报告不声称真人录音或设备播放通过。

浏览器资源由 `prepare_assets.py` 从 npm 官方源下载并校验 SHA-512，固定 vad-web 0.0.30、onnxruntime-web 1.22.0，存入忽略目录；运行时不加载 CDN。
供应商密钥始终留在后端。测试记录、访问令牌、音频、截图及浏览器资源位于 `.model-local/`，不提交 Git。
