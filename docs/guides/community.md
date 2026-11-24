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
4. 退出 A，以访客身份在社区搜索框输入帖子正文片段或公开角色名，点搜索图标或键盘搜索键，打开匹配的帖子。也可以在社区右上角粘贴分享链接。点「加入我的角色 / 开始聊天」，注册或登录账户 B。导入完成后会打开该角色的聊天页。回到社区可以在原帖评论、回复。
5. 用 B 重复导入可打开同一角色。在另一台设备上登录 B，可以从「角色」找到它。A 删除帖子后，新访问者看到链接已撤回，B 仍可与已导入的角色聊天。

## 数据归属

社区搜索接口 `GET /community/posts?q=关键词&before=帖子ID` 支持访客访问。搜索使用发帖时的公开角色名和帖子正文，匹配连续文字，英文字母忽略大小写。结果按帖子 ID 从新到旧排列，每页最多 30 条。翻页时携带同一关键词。「清除搜索」恢复全部公开帖子。撤回或下架的分享会从搜索结果中移除。

- 服务端根据登录会话确定账户。密码以带独立随机盐的 scrypt 派生值保存，服务端仅保存会话令牌摘要，有效期 30 天。退出时先清除本机登录状态，再向服务端撤销会话。离线时会在下次启动或登录时重试撤销。
- 每次发布保存一份独立的公开快照，包含名称、简介、人设、内置形象和公开音色预设。个人音色绑定、私人录音、聊天和记忆各自保存在原账户作用域。账户角色库、帖子和评论由服务端持久保存。
- 每个账户下，每个角色保留自己的 SQLite 时间线和记忆。v3 的在线历史和回听录音也按账户读取。旧网关开发令牌访问原开发空间。旧版手机记录位于本机访客空间，手动选择「我的 → 迁入本机访客记录」后，有历史的角色以独立角色迁入当前账户，原有账户角色继续可用。该操作针对手机内的记录，旧开发网关录音仍属于原开发空间。
- 在线文字、按住说话和连续通话共用导入角色的人设。在 live 模式配置既有模型和语音服务凭据，并在服务端设置 `COMMUNITY_VOICE_DEFAULT`、`COMMUNITY_VOICE_BRIGHT` 为可公开使用的供应商音色 ID。模拟模式仅用于协议测试。

## 分享网址与手机唤起

分享网址为同一服务来源下的 `/s/<分享标识>`。浏览器可预览并点「在 App 中打开角色卡」。App 同时接受此网页链接及 `erciyuan://share/<分享标识>`。链接只指定要看的角色卡，导入时使用当前登录的账户。

使用自己的 HTTPS 域名实现点击网址直接唤起 App 时，代理需转发 `/s/`、`/community/`、`/v3/`（含 WebSocket）及下列关联文件。App 的 `COMMUNITY_GATEWAY_URL` 应指向同一来源。

- Android 构建时设置 Gradle 属性 `communityShareHost`（可使用环境变量 `ORG_GRADLE_PROJECT_communityShareHost`）。服务端设置 `COMMUNITY_ANDROID_CERT_SHA256` 为实际安装包签名证书的 SHA-256 指纹，带冒号。关联文件位于 `/.well-known/assetlinks.json`。
- iOS 使用具有 Associated Domains 权限的签名配置，将 Runner 的 `CODE_SIGN_ENTITLEMENTS` 设为 `Runner/CommunityLinks.entitlements`，构建设置 `COMMUNITY_SHARE_HOST` 为实际域名。服务端设置 `COMMUNITY_IOS_TEAM_ID`。关联文件位于 `/.well-known/apple-app-site-association`。一般本地构建使用 `Runner/Runner.entitlements`。

## 独立运营后台

启用社区网关后，在浏览器打开该网关的 `/ops/`。本机沿用上面的示例端口时是 `http://127.0.0.1:18946/ops/`。部署到自己的域名时通过 HTTPS 将 `/ops/`（含静态资源和 API）与 `/community/` 转发给同一个网关。手机端的四个一级入口保持原有结构。

1. 先让运营人员注册一个社区账户。在网关机器上，通过可信渠道核对运营人员身份，再从该实例的社区数据库读取账户 ID。示例沿用上文的工作目录和数据目录，末尾参数替换为实际用户名。

   ```powershell
   python -c "import sqlite3,sys; db=sqlite3.connect('file:.model-local/community/community.sqlite?mode=ro',uri=True); print(db.execute('SELECT id FROM accounts WHERE login=?',(sys.argv[1].strip().casefold(),)).fetchone()[0])" "已核实的用户名"
   ```

2. 在网关启动环境设置 `COMMUNITY_ADMIN_IDS`，值为已核实的账户 ID，多个 ID 用英文逗号分隔，然后重启网关。默认没有管理员。移除对应 ID 并重启后，已登录的网页在下一次请求时也会失去管理权限。
3. 运营人员用该账户登录网页，可查看举报和反馈队列。处理举报可选择下架或驳回，处理反馈可直接回复。处理记录包含经办人、时间和给提交人的回复。下架角色分享会同时关闭公开链接和新导入，已导入的角色仍归各自账户。
4. 普通用户可在帖子详情举报帖子或评论，在「我的 → 反馈与处理记录」提交建议并查看自己的处理结果。
5. 工作概览按 UTC 日期统计已登录账户近 7 天或 30 天的 v3 文字、按住说话和连续通话轮数。一次已建立的轮次计一次，包含中断或失败的轮次。统计用于观察使用量；供应商 token 和费用另行核算。

## 验证

在网关环境运行 `python -m pytest tests/test_community.py tests/test_operations.py tests/test_conversations.py`。启动独立模拟网关后，在专用 Android 模拟器的 Flutter 工程运行以下命令。此用例会注册临时测试账户。

```powershell
flutter test integration_test/community_test.dart -d <设备ID> --dart-define=COMMUNITY_GATEWAY_URL=http://127.0.0.1:18946
```

完整联调在 [Community search and moderation](../../.github/workflows/community-integration.yml) 工作流中运行。Android 模拟器通过 `10.0.2.2` 连接宿主机上的临时网关，浏览器在同一实例审核帖子、评论和反馈，App 刷新后检查运营回复、分享下架和角色保留。开发机复跑时，先启动专用 Android 模拟器，在 `apps/mobile` 运行 `flutter pub get`，然后从 `services/model_gateway` 执行下列命令。

```powershell
python -m pip install -r requirements.txt playwright==1.65.2
python -m playwright install chromium
$env:ANDROID_SERIAL = 'emulator-5554'  # 按 adb devices 的结果填写
python -m pytest -q -s tests/android_community_e2e.py
```
