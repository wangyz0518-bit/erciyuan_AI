# 账户、社区与角色分享

正式 App 默认打开「陪伴」，恢复最近人物的对话。底部四个入口分别是「陪伴」「角色」「社区」「我的」。访客可以读帖和预览角色卡，注册或登录后可以发帖、评论、回复、管理自己的帖子与角色。在「我的」可登录、退出、切换账户和打开本机数据管理。登录凭据保存在系统安全存储中。

## 两个账户试用

1. 在已有模型网关 Python 环境中，从 `services/model_gateway` 启动一个社区实例。下列 PowerShell 命令使用独立数据库和模拟模型。首次启动会创建数据目录，再次使用同一目录会保留账户、帖子和角色库。

   ```powershell
   $env:COMMUNITY_ENABLED = 'true'
   $env:GATEWAY_MODE = 'mock'
   $env:GATEWAY_DATA_DIR = '.model-local/community'
   $env:GATEWAY_TOKEN = [guid]::NewGuid().ToString('N')
   python -m uvicorn gateway.app:create_app --factory --host 127.0.0.1 --port 18946 --no-access-log
   ```

2. 先用 `adb -s <设备ID> reverse tcp:18946 tcp:18946` 转发端口，再从 `apps/mobile` 在 Android 模拟器运行 `flutter run -d <设备ID> --dart-define=COMMUNITY_GATEWAY_URL=http://127.0.0.1:18946`。正式社区构建只需服务地址。真机使用自己部署的 HTTPS 地址。未指定服务地址的独立安装可进入社区，选择「连接社区服务」输入地址。
3. 注册账户 A，在「角色」创建或编辑角色，选择「分享」，核对公开角色卡，填写帖子并发布。从帖子详情复制链接。
4. 退出 A，以访客身份在社区右上角粘贴链接。点「加入我的角色 / 开始聊天」，注册或登录账户 B。导入完成后会打开该角色的聊天页。回到社区可以在原帖评论、回复。
5. 用 B 重复导入可打开同一角色。在另一台设备上登录 B，可以从「角色」找到它。A 删除帖子后，新访问者看到链接已撤回，B 仍可与已导入的角色聊天。

## 数据归属

- 服务端根据登录会话确定账户。密码以带独立随机盐的 scrypt 派生值保存，服务端仅保存会话令牌摘要，有效期 30 天。退出时先清除本机登录状态，再向服务端撤销会话。离线时会在下次启动或登录时重试撤销。
- 每次发布保存一份独立的公开快照，包含名称、简介、人设、内置形象和公开音色预设。个人音色绑定、私人录音、聊天和记忆各自保存在原账户作用域。账户角色库、帖子和评论由服务端持久保存。
- 每个账户下，每个角色保留自己的 SQLite 时间线和记忆。v3 的在线历史和回听录音也按账户读取。旧网关开发令牌访问原开发空间。旧版手机记录位于本机访客空间，手动选择「我的 → 迁入本机访客记录」后，有历史的角色以独立角色迁入当前账户，原有账户角色继续可用。该操作针对手机内的记录，旧开发网关录音仍属于原开发空间。
- 在线文字、按住说话和连续通话共用导入角色的人设。在 live 模式配置既有模型和语音服务凭据，并在服务端设置 `COMMUNITY_VOICE_DEFAULT`、`COMMUNITY_VOICE_BRIGHT` 为可公开使用的供应商音色 ID。模拟模式仅用于协议测试。

## 分享网址与手机唤起

分享网址为同一服务来源下的 `/s/<分享标识>`。浏览器可预览并点「在 App 中打开角色卡」。App 同时接受此网页链接及 `erciyuan://share/<分享标识>`。链接只指定要看的角色卡，导入时使用当前登录的账户。

使用自己的 HTTPS 域名实现点击网址直接唤起 App 时，代理需转发 `/s/`、`/community/`、`/v3/`（含 WebSocket）及下列关联文件。App 的 `COMMUNITY_GATEWAY_URL` 应指向同一来源。

- Android 构建时设置 Gradle 属性 `communityShareHost`（可使用环境变量 `ORG_GRADLE_PROJECT_communityShareHost`）。服务端设置 `COMMUNITY_ANDROID_CERT_SHA256` 为实际安装包签名证书的 SHA-256 指纹，带冒号。关联文件位于 `/.well-known/assetlinks.json`。
- iOS 使用具有 Associated Domains 权限的签名配置，将 Runner 的 `CODE_SIGN_ENTITLEMENTS` 设为 `Runner/CommunityLinks.entitlements`，构建设置 `COMMUNITY_SHARE_HOST` 为实际域名。服务端设置 `COMMUNITY_IOS_TEAM_ID`。关联文件位于 `/.well-known/apple-app-site-association`。一般本地构建使用 `Runner/Runner.entitlements`。

## 验证

在网关环境运行 `python -m pytest tests/test_community.py tests/test_conversations.py`。启动独立模拟网关后，在专用 Android 模拟器的 Flutter 工程运行以下命令。此用例会注册临时测试账户。

```powershell
flutter test integration_test/community_test.dart -d <设备ID> --dart-define=COMMUNITY_GATEWAY_URL=http://127.0.0.1:18946
```
