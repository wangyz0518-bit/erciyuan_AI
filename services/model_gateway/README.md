# 本机声音网关

手机沉浸聊天页使用用户上传的 v3 实现。三种输入共享同一人物的上下文，文字由 DeepSeek 生成，按住说话和连续通话由 Qwen 实时转写，角色回复使用已绑定的 CosyVoice 克隆音色。协议及旧版接口见[原工程的 v3 契约](https://github.com/wangyz0518-bit/erciyuan_AI/blob/8d556655ebbc6bd1a78701d0047df589ffad5161/docs/接口/model-gateway-conversation-v3.md)。

在 Python 3.12 环境安装 `requirements-lock.txt`，然后从此目录运行：

```powershell
./run.ps1 -Mode live -Python <Python可执行文件> -KeyRoot <本机DeepSeek凭据目录> -VoiceConfigRoot <本机百炼凭据目录> -LocalRoot <本机运行目录>
```

默认端口为 8787，监听本机回环地址。若使用本机已配置的 HTTPS 代理，添加 `-UseExistingProxy`。运行目录中的 `gateway-live/voice_profiles.sqlite` 保存音色绑定，`gateway-live/conversations-v3.sqlite` 保存 v3 对话和录音。已有绑定可使用原运行目录或一致的 SQLite 本机备份。网关生成的 `mobile-live.json` 仅供本机开发构建。

从此目录运行 `python -m pytest -q` 可执行离线后端测试。浏览器预览使用[独立的浏览器网关](../person_gateway/README.md)。
