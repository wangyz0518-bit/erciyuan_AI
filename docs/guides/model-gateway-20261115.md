# DeepSeek 与 CosyVoice Flash 本机联调

> 状态：评审中
> 日期：2026-11-15
> 分支：`codex/deepseek-cosyvoice-gateway`，基于沉浸聊天 `614ccad`

后端入口 `services/model_gateway`，Flutter 入口 `apps/mobile_poc`。接口见 [v0 契约](../接口/model-gateway-v0.md)，结果见 [验收记录](../reports/model-gateway-20261115.md)。没有配置网关时，Flutter 仍运行原来的离线模拟模式。

## Windows

在仓库根目录，用 Python 3.12 建立独立环境：

```powershell
python -m venv D:\dev\model-gateway-venv
D:\dev\model-gateway-venv\Scripts\python.exe -m pip install -r services/model_gateway/requirements-lock.txt
pwsh -File services/model_gateway/configure-deepseek.ps1
pwsh -File services/model_gateway/run.ps1 -Mode live -Port 8787
```

配置脚本隐藏输入，并使用当前 Windows 账号加密保存 DeepSeek Key。服务默认读取 `.model-local/deepseek-key.dpapi`；声音读取已有声音工作树 `.worktrees/d-voice-desktop/.voice-local/` 的加密 Key、北京区配置和 Flash 音色清单。其他工作站可传 `-VoiceConfigRoot`，或使用后文环境变量。不要复制 Windows 加密文件到其他人的电脑，DPAPI 文件不能跨账号通用。

模型 Key 不会写入手机配置。服务会产生 `.model-local/mobile-live.json`，其中只有本机地址和独立开发令牌。不要把此配置或安装包当作公开生产应用发布；所有 `.model-local/` 文件均忽略，不上传 Git。

服务运行后，在另一个终端执行（用 `adb devices` 确定设备）：

```powershell
D:\dev\android-sdk\platform-tools\adb.exe -s emulator-5556 reverse tcp:8787 tcp:8787
pwsh -File apps/mobile_poc/tool/windows.ps1 -Action run -Device emulator-5556 -GatewayConfig D:\codex\erciyuan_AI\.model-local\mobile-live.json
```

本机通过 adb reverse 让安卓的 `127.0.0.1:8787` 转到 Windows。重启设备后要重建转发。Android 仅 Debug 配置放行回环地址/模拟器主机别名的 HTTP，发布版不放宽明文网络。

服务应显示 `/health` 的 mode=live、chat_configured=true、voice_configured=true；这只说明配置存在，不代表真实调用已通过。`/docs` 提供接口定义及请求测试入口，调用业务接口需填写 Authorization 头。后台进程默认不记录访问日志；不把原始错误、聊天内容和凭据写入公共日志。

## macOS / iOS 同伴

拉取本任务分支后另开自己的开发分支。安装相同 Flutter/Dart 版本（当前 Android 构建使用 Flutter 3.50.0 / Dart 3.14.0），Python 环境安装上述 requirements。后端不依赖 Windows；参考 `services/model_gateway/.env.example`，在本地环境设置 `GATEWAY_TOKEN`、`DEEPSEEK_API_KEY`、`DASHSCOPE_API_KEY`、已创建的 `COSYVOICE_VOICE_ID` 等。该文件只是模板，程序读取环境变量，不自动加载 `.env`。

```sh
cd services/model_gateway
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-lock.txt
# 在本机终端配置环境变量，不把真实值复制到共享说明或 Git。
python -m uvicorn gateway.app:create_app --factory --host 127.0.0.1 --port 8787 --no-access-log
```

在另一终端为 Flutter 准备本机 JSON（字段 MODEL_GATEWAY_URL、MODEL_GATEWAY_TOKEN），运行 `flutter run -d <ios-device-id> --dart-define-from-file=<local-json>`。iOS 模拟器与后端同 Mac 时可使用回环地址；真机需要可达的 HTTPS 开发地址以及签名配置。iOS 的网络策略、录音权限、播放器、后台行为需要同伴实际构建验证，本次 Windows 工作不能代替 iOS 验收。供应商 Key 始终只在 Python 端。

## 检查与故障注入

```powershell
# 后端测试全部使用替身，不调用付费模型。
cd services/model_gateway
D:\dev\model-gateway-venv\Scripts\python.exe -m pytest -q
cd ../..
pwsh -File apps/mobile_poc/tool/windows.ps1 -Action analyze
pwsh -File apps/mobile_poc/tool/windows.ps1 -Action test
pwsh -File apps/mobile_poc/tool/windows.ps1 -Action gateway -Device emulator-5556 -GatewayConfig D:\codex\erciyuan_AI\.model-local\mobile-live.json
pwsh -File apps/mobile_poc/tool/windows.ps1 -Action suite -Device emulator-5556
```

gateway 测试的第一项调用配置的后端：live 模式会发送固定合成短句并产生模型用量；第二项用受控替身注入声音失败和迟到音频。suite 维持原有五项离线集成验收，麦克风权限需在测试安装后授予。使用专用测试模拟器，因为 Flutter 集成测试可能重装应用。

无 Key 时可另开终端 `run.ps1 -Mode mock -Port 8788`，使用生成的 mobile-mock.json，并增加 8788 的 adb reverse。mock 返回明确模拟文字和静音 WAV，只验证接口传输，不能算真实模型或声音听感通过。

单次后端真实短句检查：

```powershell
D:\dev\model-gateway-venv\Scripts\python.exe services/model_gateway/smoke.py --token-file .model-local/gateway-token.txt --output .model-local/smoke-live
```

文字失败看稳定错误码；声音失败可单独重试。不要盲目循环重试付费接口。新请求到来时清理超过 24 小时的已结束本机请求；服务重启保留完成结果，未完成请求明确失败，不自动重发。开发数据库不是正式聊天备份。
