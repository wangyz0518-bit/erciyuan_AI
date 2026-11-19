# Windows 三种聊天方式测试指南

> 状态：评审中，Windows 人工验收待补，Android 已有调试接入
> 日期：2026-11-18
> 负责人：待定
> 关联：A/B/D、[v3 契约](../接口/model-gateway-conversation-v3.md)

## 启动

在本任务工作区双击 `apps/windows_conversation_lab/Launch.cmd`。脚本准备本地语音检测资源、启动 loopback 网关，再打开默认浏览器。请使用 Edge 或 Chrome。
本机当前工作区为 `D:\codex\erciyuan_AI\.worktrees\continuous-voice`，真实服务默认端口 8788。
已有运行服务会复用，不重复启动。供应商密钥从主工作区已有 DPAPI 配置读取，不复制到客户端。
默认 Python 为本工作区 `.model-local/conversation-venv/Scripts/python.exe`，使用独立环境和网关锁定依赖，避免影响原有测试台。此工作站环境已准备；新电脑须先按网关指南配置密钥并执行：

```powershell
python -m venv .model-local/conversation-venv
./.model-local/conversation-venv/Scripts/python.exe -m pip install -r services/model_gateway/requirements-lock.txt
```

本分支将 websockets 从 15.0.1 升至 17.4，处理实测代理连接取消时的库内异常；旧环境未升级。

PowerShell 可显式启动：

```powershell
./apps/windows_conversation_lab/launch.ps1 -Route proxy
# 无代理环境可指定 -Route direct；只检查服务、不打开浏览器可加 -NoBrowser。
```

auto 模式复用已运行服务的连接方式；启动新服务时，有 HTTPS_PROXY 则使用现有进程代理，否则直连。
proxy 模式需要已有 HTTPS_PROXY。脚本不修改系统代理，不在模型失败后自动切换线路重试。
端口被不同模式/明确指定的不同线路服务占用时会报错。一个运行目录只允许一个网关，不能只换端口而共用数据库。
另起独立测试可同时指定 `-Port 8791 -RuntimeRoot '.model-local/isolated-test'`；其令牌、数据库、配置、PID 和日志均独立，不影响默认测试服务。当前服务已关闭后也可继续使用原运行目录。
代理和直连都不能保证网络始终可用，本轮直连出现过建连超时，保留了失败记录。

## 使用

1. 页面显示“已连接 · 真实模型”后，可先打字发送。自动朗读可关闭。
2. 点“启用麦克风”，在浏览器允许本页面使用麦克风，等待“麦克风已就绪”。准备过程可取消，超时有提示。
3. 按住按钮说话，松开发送；按住期间向上拖动再松开取消。最长一段 30 秒。已发送的语音消息可“回听语音”，再点“停止回听”可停止；挂断或切换角色也会停止，迟到的下载不会重新播放。
4. 点“连续通话”，直接说话；检测到约 2.56 秒静音后自动提交，回复时可以插话。如果上一句还在识别，新一句会在本页暂存，依次提交。可静音、恢复、挂断。
5. 换角色、刷新、隐藏/离开页面会结束输入与输出，不自动恢复收费任务。页面不持久保存令牌；刷新后请关闭旧页面，再用启动脚本打开，历史会从本测试库恢复。若提示其他页面占用服务，先关闭旧聊天页面，再点“连接”。

本页新产生的每轮消息下方显示延迟，点击可展开。连续通话从最后一个检测到人声的音频帧估算说完时间，语音消息从松手计时，文字从发送计时。首字和开始播放按浏览器收到首个回复文字和音频开始渲染计时。阶段耗时包含传输与调度；刷新前的耗时不保存在聊天记录里。

识别和回复会访问云模型。按住录音的原音频保存在本机；连续通话不保存原音频，只保存识别文字与回复。
页面“连接与验证信息”显示录音设备报告的 AEC 状态及播放估计。浏览器报告开启 AEC 不等于外放回声已经验收通过。

## 音色

网页可以选择已保存的音色并应用到当前角色。初次启动复制主网关已有 ready 音色与绑定到独立测试库，不复制聊天或私人录音。
录音上传、复刻、试听仍使用已有 Windows 音色管理窗口。要管理**同一个测试网关**，先关闭聊天网页，再从本工作区执行：

```powershell
./apps/windows_voice_lab/run.ps1 -Config .model-local/mobile-live.json
```

在旧窗口的“音色管理”完成操作后，重新打开新聊天网页即可读取同库音色。勿同时在两个窗口发起声音任务。
新网页暂不提供上传复刻面板；原窗口的记录与新聊天历史不自动互相迁移。

## 人工验收门槛

| 检查 | 操作 | 应观察的结果 |
| --- | --- | --- |
| 语音消息 | 按住说两句，松开；再上滑取消一条 | 成功消息有文字和原录音；取消条不触发回答 |
| 连续对话 | 连续交流至少 5 轮，含短句和长停顿 | 不需逐次点击发送，不抢话、不把一句话切碎 |
| 外放插话 | 角色回答中插话至少 5 次 | 迅速停播，听清新问题，旧声音不恢复 |
| 回声 | 正常音量外放并保持沉默 | 不把角色自己的声音当作用户再回答 |
| 静音与恢复 | 通话中静音、恢复、挂断 | 静音不上传；恢复可继续；挂断释放麦克风 |
| 保存和切换 | 刷新、重连、换角色 | 历史恢复、角色隔离；不自动重播 |

请分别记录耳机和扬声器、浏览器、输入设备与主观听感。自动测试、合成参考音频、网页播放帧计数不能替代这些检查。
已按用户指示开始 Android 接入，见 [Android 连续语音测试版](android-conversation-v3.md)。Windows 外放与真人通话的验收项继续保留。

## 自动验证

```powershell
# services/model_gateway 目录
python -m pytest -q
# 仓库根目录
node --test apps/windows_conversation_lab/tests/*.test.cjs
```

以下会调用付费模型，仅在明确进行真实验证时运行：

```powershell
python apps/windows_conversation_lab/live_smoke.py --config .model-local/mobile-live.json --output .model-local/conversation-validation/my-run
python apps/windows_conversation_lab/live_interrupt_smoke.py --config .model-local/mobile-live.json --reference .model-local/conversation-validation/my-run/synthetic-reference.pcm --output .model-local/conversation-validation/my-run/interrupt-smoke.json
```

第一项生成合成参考并验证 ASR→回复→TTS；第二项复用参考验证通话打断、下一轮输入和取消录音。两项均不打开麦克风、不声称用户听到了音频。
检查运行结果以 JSON 的 passed/error 为准；失败不自动重做请求。原始证据保留在忽略目录。
