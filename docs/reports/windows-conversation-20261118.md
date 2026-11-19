# Windows 连续语音阶段验证

> 状态：Windows 初版阶段记录。后续 Windows 停顿修复和 Android 联调分别见 [Windows 指南](../guides/windows-conversation-20261118.md) 与 [Android 指南](../guides/android-conversation-v3.md)。
> 日期：2026-11-18
> 负责人：待定
> 关联：A/B/D、codex/continuous-voice-windows

## 本轮实现

新增 Windows 本机浏览器测试入口、v3 会话服务、Qwen 实时 ASR、录音消息及连续通话输入。
复用 DeepSeek、CosyVoice v3.5 Flash 与已保存角色音色；没有修改 Android/iOS 页面、原生录音或手机数据库。
文字、hold、call 共用每个角色的上下文。录音上传复刻仍通过已有 Windows 音色管理窗口接同一个网关。

修复了识别结束与取消交错时的迟到回复、静音恢复后的麦克风资源跟踪、权限迟到后的资源释放、旧连接未释放就修改音色、冷建连期间收音队列过小等问题。
v3、Windows 测试目录和本机数据库均独立；原有手机及 v1/v2 回归保留。

## 自动检查

| 检查 | 结果 | 边界 |
| --- | --- | --- |
| 网关 pytest | 54 通过 | 包含旧接口/音色回归和新会话/ASR/真实本地代理取消测试，供应商用替身 |
| 浏览器状态与 PCM Node 测试 | 16 通过 | 覆盖迟到事件、麦克风生命周期、重连并发、角色音色隔离、关闭连接时的挂断/录音提交/播放进度、原录音回放、占用提示、播放时长与采样率；非声学测量 |
| Windows 浏览器 UI | 文字发送、停止回复、重连恢复、角色隔离、麦克风准备取消通过 | 模拟网关；内置浏览器未取得实际麦克风，不代表真实收音通过 |
| 真实合成参考闭环 | run-20261118-03 通过 | Qwen ASR→DeepSeek→CosyVoice，未打开麦克风或实际播放 |
| 真实通话协议打断 | run-20261118-04 通过 | 第一轮首包后取消，立即创建新输入，第二轮完成；原始通话音频未留存，取消录音未入历史 |
| 新依赖环境真实复测 | run-20261118-05 通过 | websockets 17.4 下重复两轮识别、打断、新回复和录音取消；本次日志未出现旧代理异常 |
| 实际 Launch.cmd | 服务复用及独立目录冷启动通过 | Windows PowerShell、含空格的运行路径、独立令牌/历史、v3 模拟文字回复和连接释放；未用它自动打开原生浏览器 |
| 重复运行目录保护 | 通过 | 尝试用新端口复用活动运行目录被拒绝，现有真实服务的配置哈希不变 |

真实参考台词为程序生成的“你好，我也喜欢星星，想聊点什么呢？”，识别结果与参考文字一致。
这是一次固定合成语音检查，不是中文识别率评估，不能推出噪声环境、人声、方言等场景的准确率。
实际录音/云模型延迟/外放声学打断不从 Node 或服务端事件结果推算。

## 失败和修复证据

1. 前两次直连测试在主模型建连阶段出现 MODEL_TIMEOUT；一次文字复测成功。没有把短暂成功写成网络问题彻底解决。
2. run-20261117-02 在 ASR 建连期间出现 INPUT_BACKPRESSURE。将队列从 48 块扩大到 1024 块，同时保持 30 秒/960000 字节总上限，并增加慢连接回归。
3. run-20261118-03 的首次打断测试第二轮出现 ASR_UNAVAILABLE。后续同路径复测通过；日志发现 websockets 15.0.1 代理响应 Future 已结束后继续解析产生异常。
4. 为修复代理取消异常，在 `.model-local/conversation-venv` 独立安装 websockets 17.4 和本分支锁定依赖；原有 `D:\dev\model-gateway-venv` 未升级。54 项检查是在新环境执行。
5. 后续交付检查用新增测试复现：WebSocket 已进入关闭状态但尚未派发 close 事件时，取消命令抛错会跳过本地麦克风清理；原录音下载迟到也可能在挂断后播放。取消与进度上报改为尽力发送，本地停止不再依赖网络；回放加入操作代次检查和统一停止管理。相关回归已通过。

依赖依据：[websockets 上游实现](https://github.com/python-websockets/websockets/blob/main/src/websockets/asyncio/client.py)、[发布说明](https://websockets.readthedocs.io/en/stable/project/changelog.html)。问题归因以本机栈与回归为准，不据此声称供应商全部异常都由客户端造成。

## 本机原始证据

工作区 `.model-local/conversation-validation/` 下保存：

- `run-20261117-01/synthetic-smoke.json`：主模型超时。
- `run-20261117-02/synthetic-smoke.json`：输入队列不足。
- `run-20261118-03/synthetic-smoke.json`、`synthetic-reference.pcm`：真实 ASR 闭环。
- `run-20261118-03/interrupt-smoke.json`：第一次打断测试失败。
- `run-20261118-04/interrupt-smoke.json`：打断协议复测通过。
- `run-20261118-05/interrupt-smoke.json`：独立新依赖环境复测通过。
- `windows-ui-20261118.jpg`：模拟模式页面截图，不是实际通话证明。

该目录被 Git 忽略。没有提交访问令牌、供应商配置、原始音频或完整日志。

## 尚未通过的验收

真人按住录音、至少 5 轮连续通话、外放 5 次插话、回声误触发、耳机/扬声器听感、静音恢复和实际设备延迟均待按[指南](../guides/windows-conversation-20261118.md)检查。
当前播放进度是渲染帧位置估计，没有逐字“已听内容”对齐。
当前仍在完整文字生成后开始 TTS，尚未做短句提前合成。
这份阶段记录在 Android 接入前形成。随后用户要求开始 Android 接入，模拟器和真机的验证进度见上方 Android 指南。
