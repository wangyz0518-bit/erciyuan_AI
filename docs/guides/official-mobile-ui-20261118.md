# 正式移动端人物主页与持续聊天使用说明

适用：`apps/mobile/`，Issue #37，Flutter 3.50。

## 启动

```bash
cd apps/mobile
flutter pub get
flutter run
```

初次运行在设备本地 SQLite 中创建示例人物“小星”“小月”，并进入 A 方案人物主页。点击人物卡选择，或点击右侧箭头直接进入该人物聊天。底部“继续与 TA 对话”始终进入其唯一、持续的时间线，不存在新建会话或切换会话功能。

再次启动会显示人物主页，若有历史互动则自动高亮最近发过消息的人物。不同人物消息、记忆和模型请求通过 `owner_id + character_id` 严格隔离。人物草稿暂为内存状态，重启后不恢复草稿；已发送消息是 SQLite 持久数据。

## 默认离线模式

默认运行 **离线 Mock**，界面、文本及回复都明确标记 Mock，Mock 回复并非真实 AI。Mock 模式仍使用正式 `generation_tasks` 与 `raw_events` 数据结构保存原始事实。

## 受控开发文字网关

已有 #39 的 `ModelGatewayAdapter` 可在开发设备上接入受控网关：

```bash
flutter run \
  --dart-define=PERSON_GATEWAY_URL=http://10.0.2.2:8000/ \
  --dart-define=PERSON_GATEWAY_DEV_TOKEN=temporary-local-test-token
```

`10.0.2.2` 仅为 Android Emulator 到开发主机的地址；真机及 iOS 需使用其网络可达的开发服务地址。网关须按 #39 服务端文档配置人物白名单、开发鉴权、网络环境和隐私边界，且不得直接把真实模型厂商 API 密钥交给 App。

**安全边界：`--dart-define` 会将配置打包进二进制，不能用来储存生产密钥。只能在离线/本机受控环境使用无特权、可撤销、短期开发令牌。** 未经允许不调用付费 AI，不上传个人数据。

## 操作与数据出口

- 聊天上方显示静态人物占位与 Mock/网关状态；中间显示真实 SQLite 历史、流式回复提示，底部为文字输入。
- 回复失败后可手动重试；取消按钮可中止正在等待的回复。如果无法确定网关结果，先点“查询原请求”，避免重复计费/重复回复。
- 右上角人物菜单直接切换到另一位人物的唯一持续聊天时间线。
- 主页右上角“我的 / 数据管理”→“一键导出并复制全部 JSON”：导出该本地 owner 的完整人物、原始历史、归档、摘要、身份版本与生成任务，复制到剪贴板供用户保存在可信本地文件中。不会自动上传，也不会删除数据库。
- 导出含完整私人聊天内容，系统剪贴板可能被其他软件读取，请谨慎选择保存目标。

## 本地验证

```bash
cd apps/mobile
dart format --output=none --set-exit-if-changed lib test test_screenshots
flutter analyze
flutter test
flutter test --update-goldens test_screenshots/official_ui_preview_test.dart
flutter build apk --debug
```

正式 UI 的截图由 **Flutter Widget 渲染**生成，不代表人工实际点按或 Android 真机测试；相应 CI 同步上传 `erciyuan-mobile-ui-preview-375px` 和 `erciyuan-mobile-android-debug` 产物。

iOS/macOS 见 #40，Android 真机见 #41，音频和 Live2D 分别见 #42–#44。未实测的项目不得宣称通过。
