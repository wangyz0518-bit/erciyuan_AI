# 在 Mac 上把陪伴 App 装到自己的 iPhone

在 Mac 上克隆语音 PoC 分支，然后从仓库根目录运行下文命令。使用单独的工程包时，解压后进入 `Companion-iPhone-Test` 即可。iPhone 通过 USB 安装，语音对话通过同一局域网访问 Mac 上的测试网关。

```bash
git clone --branch codex/ios-voice-handoff --single-branch https://github.com/wangyz0518-bit/erciyuan_AI.git
cd erciyuan_AI
```

### 给移植开发者

- [Flutter 会话控制器](../../apps/mobile_poc/lib/conversation_controller.dart) 管理三种输入、断句、排队、打断和每轮延迟。相邻的 `conversation_capture.dart`、`conversation_transport.dart` 分别负责采集分帧和网关通信。
- [iOS 原生入口](../../apps/mobile_poc/ios/Runner/AppDelegate.swift) 注册检测和播放通道。[本地 Swift 包](../../apps/mobile_poc/ios/ConversationVAD) 运行 Silero 检测，[流式播放器](../../apps/mobile_poc/ios/Runner/ConversationPlayer.swift) 负责播报、播放进度和停播。移植时一起复制 [ONNX 模型及许可](../../apps/mobile_poc/android/app/src/main/assets)，Xcode 的 Copy Bundle Resources 引用了该目录。
- [会话 v3 契约](../接口/model-gateway-conversation-v3.md) 和 [测试网关](../../services/model_gateway/ios_test_gateway.py) 可用于独立联调。正式 App 位于主分支的 `apps/mobile`，移植时请对接其现有角色、权限和历史存储。

Git 克隆版可以直接启动模拟网关。真实语音可使用测试账号自己的默认音色。若要复用「蜜糖泡芙」和「晚棠」，把此前私下交付的工程包中的 `test-voices.json` 复制到仓库根目录；网关会查询当前百炼账号能访问的音色。该目录文件已加入 Git 忽略。

## 准备

- 在 Mac 安装能识别这台 iPhone 的 Xcode，启动一次完成组件安装。在 Xcode → Settings → Accounts 添加你自己的 Apple 账号。普通账号将显示为 Personal Team，设备配置有效期为 7 天，到期后重新运行安装脚本即可。[Apple 账号与设备测试](https://developer.apple.com/help/account/basics/about-your-developer-account)
- 开发机使用 Flutter 3.50.0（Dart 3.14.0）和 Python 3.12。先执行 `flutter doctor -v`，完成 Xcode 工具链一栏的设置；首次构建需要互联网下载 Flutter 插件和 ONNX Runtime。[Flutter iOS 环境](https://docs.flutter.dev/platform-integration/ios/setup)
- 用数据线连接并解锁 iPhone，按提示信任 Mac。如果系统要求，在「设置 → 隐私与安全性 → 开发者模式」中启用，重启后确认。[Apple 开发者模式](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- 真语音需要测试方可使用的 DeepSeek 和阿里云百炼北京区 API Key。模型密钥只在 Mac 的终端输入。两台设备连接同一个允许设备互访的 Wi-Fi。

## 安装

1. 打开终端，输入 `cd `，把解压后的文件夹拖入终端，按回车。启动网关并确认 Mac 的 Wi-Fi 地址。保持这个终端开着。

   ```bash
   bash tools/ios_mac/start-gateway.command
   ```

   首次启动会创建独立 Python 环境。按提示输入密钥，屏幕不会回显。若账号需要指定百炼业务空间，先在当前终端设置 `DASHSCOPE_WORKSPACE_ID`。网关会用当前账号查询「蜜糖泡芙」和「晚棠」两个已设计音色。可用的会出现在 App 的「角色声音」中。其他业务空间可能没有这两个音色，此时请按提示填入自己账号可用的 CosyVoice v3.5 Flash 默认音色 ID。语音识别、回复和朗读会产生相应的模型用量。

   如果只想先看界面、发模拟文字，在上述命令末尾加 `--mock`。测试真人录音识别和连续对话时，关闭模拟网关并运行正常命令。

2. 再打开一个终端，进入同一文件夹，运行安装脚本。

   ```bash
   bash tools/ios_mac/install-iphone.command
   ```

   脚本准备 Flutter 工程并打开 Xcode。选择左侧蓝色 **Runner** 工程 → **TARGETS / Runner** → **Signing & Capabilities**，勾选 **Automatically manage signing**，选择自己的 **Personal Team**。如果 Bundle Identifier 已被占用，改为自己独有的反向域名，例如 `dev.你的英文标识.companiontest`，请将示例中的中文替换为英文字母。签名配置应用于 **All** 或 **Release**。

3. 回到终端按回车，从设备清单复制 iPhone 的设备 ID，粘贴并回车。脚本构建可从主屏幕启动的 Release 开发版并装到手机。如果首次打开时系统要求信任开发者，在「设置 → 通用 → VPN 与设备管理」中按提示确认。第一次进入聊天和录音时，分别允许本地网络和麦克风。

Mac 地址和网关配置会写入本机的 `.model-local/ios-mac/`。App 在构建时取得测试网关地址、开发令牌和公有证书。手机与 Mac 的连接使用 HTTPS 和 WSS。Mac 更换 Wi-Fi 地址、证书更新或换电脑时，重新启动网关并运行安装脚本。系统防火墙询问时允许 Python 在当前可信网络接收连接。

## 真机试这三件事

1. **按住说话。** 按住说一句，松手。确认看到转写、收到角色回复、能回听原录音。再按住说话，移出按钮后松手，确认取消。
2. **连续说两句。** 进入连续通话，说“我今天想看星星”，停约两秒，再说“你觉得几点出门合适”。第二句说完后等角色回复，确认两句都在同一条消息里。当前静音断句约 2.56 秒。消息下方可以看本轮断句、转写、回复首字和开播耗时。
3. **播报中插话。** 在角色播放时说“等一下，我们换个话题”，确认旧声音停止、新问题得到回复。另用正常外放音量保持沉默，观察有无误打断。可切换耳机和已有音色再试，记录设备型号、iOS 版本和有问题的步骤。

截至本次交付，安卓模拟器通过采集、两句停顿、排队和打断复测。iOS 工程已接入相同模型和断句逻辑，已对 Xcode 工程结构、Swift 语法、人声检测核心与网关连接做开发机检查。实际 Xcode 编译签名、iPhone 音频路由、回声与听感由本次真机测试确认。
