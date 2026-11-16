# Windows 录音复刻操作与复测

> 状态：评审中
> 日期：2026-11-16
> 负责人：待定
> 关联：D 声音、codex/recording-voice-cloning

## 启动

依赖 Python 3.12，网关和 Windows 客户端分别安装各自 `requirements-lock.txt`。新增 imageio-ffmpeg wheel 内置解码程序，放在 Python 环境中；无需修改系统 PATH。本机环境在 D 盘。

在仓库根目录启动网关（沿用已配置的安全本机密钥；`-UseExistingProxy` 只在当前已有 HTTPS_PROXY 时使用）：

```powershell
./services/model_gateway/run.ps1 -UseExistingProxy
./apps/windows_voice_lab/run.ps1
```

本机供应商密钥仍由服务端从既有 DPAPI 文件读取。Windows 客户端只读 `.model-local/mobile-live.json` 中的回环网关地址与开发令牌。详细密钥配置见[模型网关指南](model-gateway-20261115.md)。不要把真实配置发给伙伴或放进截图。

## 使用

1. 在主界面选择小星/小月与播放设备，点“自定义声音”。
2. “选择录音”支持 WAV/MP3/M4A。推荐 10–20 秒清晰单人语音，允许 10–30 秒、≤10 MiB、≥16 kHz。选择后可先“听原录音”。
3. 填名称并勾选有权使用、同意提交到声音服务；点“开始复刻并保存”。只选择文件或听原录音不会上传。
4. 创建成功后列表显示“可用”。在下方填写**要朗读的台词**，点“生成试听”，完成后点“播放试听”。此处不接受音色文字描述，也不调用 DeepSeek。
5. 满意后点“应用到当前角色”。下一次聊天使用该声音；另一角色保持原选择。“恢复默认声音”保留音色列表。
6. 关闭窗口回到聊天，正常输入、流式朗读、停止、重试；文字和角色隔离沿用原实现。

网络异常先刷新列表核实。显示待核实不能重复创建；明确失败可重试。取消创建不等于删除云端结果，稍后可能在列表出现可用音色。关闭并重开不会自动发声。

## 隔离验收数据

可指定测试库，避免把固定验收台词加入日常聊天：

```powershell
./apps/windows_voice_lab/run.ps1 -Data 'D:\codex\erciyuan_AI\.model-local\recording-clone-acceptance\ui.sqlite'
```

默认原聊天库仍是 `.model-local/windows-voice-lab/history.sqlite`；本轮没有迁移或清空它。音色目录与角色选择由网关保存，不随 Windows 测试库切换。

自动验收工具会真实上传指定参考、付费调用模型并播放声音。先只用有权使用的合成参考；运行时不要同时在主界面发消息。

```powershell
& 'D:\dev\windows-voice-lab-venv\Scripts\python.exe' apps/windows_voice_lab/clone_acceptance.py `
  --config .model-local/mobile-live.json `
  --reference .worktrees/d-voice-desktop/.voice-local/comparison-reference/reference.wav `
  --output .model-local/recording-clone-acceptance/live --warm-trials 20
```

该参考只在当前开发机存在，不随 Git 分发。工具会复用同文件音色、试听三句、应用到小星、发 21 次固定短句、测停止与重试，并重开独立历史库；输出保存在指定忽略目录。首条不计入 20 条热连接统计，但它可能已复用前面的试听连接，**不可称为冷启动数据**。

出声延迟使用 PortAudio 设备输出时钟估算，不包含远程桌面到耳机的传输，也不是麦克风测得的声学延迟。零缓冲断流不能替代对电音、断词和相似度的人工试听。

## 回归

```powershell
# 在 services/model_gateway
& 'D:\dev\model-gateway-venv\Scripts\python.exe' -m pytest -q
# 在 apps/windows_voice_lab
& 'D:\dev\windows-voice-lab-venv\Scripts\python.exe' -m unittest discover -s tests -v
```

验收口径与已知问题见[本轮报告](../reports/recording-voice-cloning-20261116.md)，字段、去重和保存规则见[接口契约](../接口/recording-voice-profiles-v0.md)。当前仍是单用户本机验证服务；Android/iOS 自定义声音界面本轮未实现、未验收。
