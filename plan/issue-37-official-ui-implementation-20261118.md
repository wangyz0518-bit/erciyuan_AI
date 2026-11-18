# Issue #37：正式人物主页与持续聊天实现记录

更新：2026-11-18。关联 [Issue #37](https://github.com/wangyz0518-bit/erciyuan_AI/issues/37) 与 [PR #59](https://github.com/wangyz0518-bit/erciyuan_AI/pull/59)。

## 目标与边界

采用 #14 的 A 版人物主页优先；每个人物仅有一条持续存在的逻辑时间线。消息和草稿按 owner_id + character_id 隔离；绝不提供创建、切换或重置会话的用户入口。语音/通话/Live2D 的真实实现由 #42–#44 完成。

## 已有 PR 复用决策

| 来源 | 处理方式 | 原因 |
| --- | --- | --- |
| #15 沉浸聊天原型 | 已合并为设计参考 | 独立原型，经评审，不影响正式工程 |
| #16 Flutter 沉浸聊天 | 适配交互，不整分支合并 | 旧 PoC、原有音频与数据模型、积累的大范围历史改动和分支冲突 |
| #33 A/B 主页 | 采纳 A 信息架构、B 留作对照 | A 的人物入口符合已确认的产品主体模型，避免 B 被误做多会话 |
| #36 SQLite | 直接使用 | 正式人物目录、原始消息与全量数据导出，非演示内存历史 |
| #39 ModelGatewayAdapter | 受控开发环境中直接使用 | 使用已有 SSE 状态、取消、重试、状态核对接口，不重新实现网关协议 |

## 功能落地

1. 启动时打开 SQLite 人物库，首次初始化两位本地示例人物，后续始终从已保存目录读取。
2. 人物主页使用角色卡和当前角色继续入口；进入后以人物 scope 打开唯一聊天时间线。
3. 聊天页包含独立草稿、可滚动完整原始事实历史、文字输入、流式增量及回复状态。
4. 无开发网关时明确显示“离线 Mock”；Mock 用户消息、生成任务、完整回复也写入 SQLite。
5. 接入开发网关时复用 #39 的发送、取消、重试和未知结果查询，未知状态未确认前不允许盲目重试。
6. 人物切换切换的是整个数据主体，迟到回复按原人物 scope 继续处理，不会显示到另一个人物下。
7. “我的 / 数据管理”使用 #36 的全量 owner JSON 导出，用户显式复制全部 JSON 到剪贴板。
8. CI 生成 375×812 Flutter Widget 渲染预览，并继续运行静态检查、单元/Widget 测试与 Android Debug APK 构建。

## 测试计划与实际证据

- `flutter analyze`
- `dart format --output=none --set-exit-if-changed lib test test_screenshots`
- `flutter test`：人物首页、人物隔离、真实 SQLite 保存与导出、Mock 取消和重试
- `flutter test --update-goldens test_screenshots/official_ui_preview_test.dart`：实际 Flutter Widget 截图（非原生设备截图）
- `flutter build apk --debug`
- 自动化结果以 PR #59 的 GitHub Actions 为准，失败必须修复，不得写成已通过。
- Android 模拟器、Android 真机、iOS 真机、真实付费模型和人物美术效果需分别验收，不能互相替代。

## 已知限制与后续

- 默认模式是离线 Mock，不代表真实付费模型联调验收。
- 目前仍使用临时静态人物图标；正式人物素材和 Live2D 见 #44。
- JSON 当前通过系统剪贴板导出，尚无系统分享/文件存储 UI；数据包含敏感内容，只有用户明确触发才会复制。
- 受控开发网关调试凭据不得作为生产令牌放入 APK。
- 首版仅负责完整交互流程与可靠数据边界，视觉统一微调在可运行版本验证后进行。

此记录描述公共产品与测试事实，不定义任何个人账号权限、审批习惯或协作限制。


## 2026-11-18 完成后证据更新

- [PR #59](https://github.com/wangyz0518-bit/erciyuan_AI/pull/59) **已合并**（squash `644e07a4beddcb3649d35783c8f4181dc5d803e1`），[Issue #37](https://github.com/wangyz0518-bit/erciyuan_AI/issues/37) 已关闭为完成。
- Flutter 主 CI [#44344224037](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44344224037)：Dart format、flutter analyze、全部单元/Widget 测试、三页 Flutter 截图、Android Debug APK、Python 网关离线测试均 **成功**。
- Android API36 官方工程模拟器 [#44344224115](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44344224115)：启动、截图以及 `integration_test/acceptance_test.dart` 与 `storage_failure_test.dart` 均 **成功**。这是模拟器证据，**不是 #41 真机**。
- 未验证及后续范围：#40 iOS Simulator、#41 物理 Android、#42 音频、#43 ASR/TTS、#44 Live2D 与 #39 真实付费模型调用。首版人物图像仍为占位素材；剪贴板数据导出为用户显式操作，非自动云上传。
