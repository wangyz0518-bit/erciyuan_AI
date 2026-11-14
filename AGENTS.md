# 项目规则

本文件供 AI 编码助手与团队成员快速了解项目边界。技术栈确定后需同步更新。

## 项目

二次元 AI 陪伴 App，面向手机使用，计划支持角色形象、声音和性格定制，以及文字、语音交流和简单表情表现。

## 当前阶段

仓库包含规划文档及 `apps/mobile_poc` 本地能力验证工程。真实 AI 服务尚未接入；模拟器验证不能代替 Android/iOS 真机验收。

第一阶段目标：

- 手机文字聊天骨架。
- 角色与对话记录可保存、可恢复。
- 形象能力、声音能力分别完成验证。

首版平台范围按 [ADR-0002](docs/decisions/0002-three-platform-scope.md) 执行：Android、iOS；原生鸿蒙后续适配，具体时间另行确定。原生鸿蒙不是首版交付、PoC 或验收条件，不据此扩大首版范围。

首版移动端采用 **Flutter + Dart**，见 [ADR-0001](docs/decisions/0001-mobile-stack.md)。

## 目录

- `docs/`：文档索引入口，详见 `docs/README.md`。
- `docs/state.md`：当前阶段、待办、风险。
- `docs/process/`：团队安排、协作流程、文档规范。
- `docs/research/`：移动端选型调研与复核。
- `docs/decisions/`：架构与选型决策记录（ADR）。
- `docs/guides/`：配置与操作指南。
- `docs/接口/`：跨工作线接口约定与样例（暂缓整理）。
- `planning/`：开发计划、Word 文档与生成脚本。
- `planning/output/`：正式 Word 计划，保留原版本，不随意覆盖。
- `planning/assets/`：规划配图；聊天界面图为概念示意，不是运行截图。

Flutter PoC 工程位于 `apps/mobile_poc`，分层与运行方法见 [运行指南](docs/guides/flutter-poc-guide-20261112.md)。继续由 [#10](https://github.com/wangyz0518-bit/erciyuan_AI/issues/10) 跟踪双端验证。

C 线 Live2D 组件位于 `packages/live2d_avatar`，Android 独立预览入口为 `apps/mobile_poc/lib/main_live2d.dart`。首次构建本分支前，在仓库根目录运行 `pwsh -File apps/mobile_poc/tool/live2d.ps1 -Action prepare`；SDK 和模型仅保留本地。之后可用 `-Action run` 运行独立 `live2d` flavor。原 PoC 默认使用 `poc` flavor。范围与验收见 [Live2D 指南](docs/guides/live2d-flutter-poc-20261112.md)，iOS 插件尚未实现。

## 命令

在 `apps/mobile_poc` 中运行：

```sh
flutter pub get
flutter run -d emulator-5554
flutter analyze
flutter test
flutter test integration_test/acceptance_test.dart -d emulator-5554 --reporter expanded
flutter test integration_test/soak_test.dart -d emulator-5554 --reporter expanded
flutter build apk --debug
```

Windows 环境辅助脚本为 `tool/windows.ps1`，用法见运行指南。集成测试期间不要同时手动操作模拟器。PoC 本地数据模型不是服务端接口契约。

## 协作约定

- 先读 `CONTRIBUTING.md`、`docs/process/team-development.md`、`docs/README.md` 和本文件。
- 日常开发使用任务分支，完成后向 `main` 发起 PR；不直接 push `main`。
- 提交信息使用 Conventional Commits，例如 `feat(a-chat): ...`、`docs(interface): ...`。
- 接口字段的含义变更或删除，必须同步更新调用方和 `docs/接口/`。
- 验收记录区分真实能力、模拟结果、未接通和失败项。
- 修改 Word 计划时保留原版本，并记录版本变化。

## 安全与数据

- 不提交密钥、令牌、`.env`、真实聊天记录、私人录音和未经确认的个人资料。
- 示例配置只使用占位值；密钥由服务端持有，客户端不打包。
- 日志和截图中的个人信息、密钥、内网地址需脱敏。

## 禁止

- 未经确认修改接口或数据模型。
- 把规划目标、模拟结果标成已完成。
- 用 `git push --force` 覆盖公共分支历史。
- 大规模改写无关文档，或提交大量排版产物。
