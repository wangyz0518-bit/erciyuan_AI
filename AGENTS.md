# 项目规则

本文件供 AI 编码助手与团队成员快速了解项目边界。技术栈确定后需同步更新。

## 项目

二次元 AI 陪伴 App，面向手机使用，计划支持角色形象、声音和性格定制，以及文字、语音交流和简单表情表现。

## 当前阶段

仓库处于规划与团队协作准备阶段，尚无产品代码或可运行应用。

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

Flutter 工程目录与分层约定随 [#10 Flutter 双端 PoC 与工程初始化](https://github.com/wangyz0518-bit/erciyuan_AI/issues/10) 建立。

## 命令

当前没有构建、测试或启动命令。

工程初始化时，在本节补充安装、开发、测试、lint、构建命令，并保持与实际脚本一致（#10）。

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
