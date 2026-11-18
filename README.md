# 二次元 AI 陪伴软件 · erciyuan_AI

面向手机使用的 AI 陪伴产品，计划支持角色形象、声音和性格定制，以及文字、语音交流和简单表情表现。

## 已确认方向

- 首版平台：**Android、iOS**；原生鸿蒙后续适配，见 [ADR-0002](docs/decisions/0002-three-platform-scope.md)。
- 首版移动端技术栈：**Flutter + Dart**，见 [ADR-0001](docs/decisions/0001-mobile-stack.md)。

## 从这里开始

1. 阅读 [项目规则](AGENTS.md)，了解项目约束。
2. 阅读 [团队协作规则](CONTRIBUTING.md)，了解 Issue、分支和 PR 流程。
3. 阅读 [产品计划](plan/README.md)，了解产品目标和阶段路线。
4. 阅读 [文档索引](docs/README.md)，查找设计、决策、指南和验证报告。

## 移动端工程

Flutter 工程位于 [apps/mobile_poc/](apps/mobile_poc/README.md)。当前是本地能力验证基线，包含 Android/iOS 工程目录、聊天/角色/录音播放 PoC 和自动化测试；真实 AI 服务尚未接入。

开发环境、命令和验证边界见 [Flutter 开发与验证指南](docs/guides/flutter-poc-guide-20261112.md)。Android 模拟器的历史验证结果见 [Android PoC 报告](docs/reports/android-poc-report-20261112.md)。

## 获取项目

```sh
git clone https://github.com/wangyz0518-bit/erciyuan_AI.git
cd erciyuan_AI
```

按 Flutter 指南安装对应版本的 Flutter SDK 和 Android 工具链，再进入 `apps/mobile_poc/` 执行依赖安装、检查和构建。

## 目录

- `apps/mobile_poc/`：Flutter 移动端本地能力验证工程。
- `AGENTS.md`：项目约束与 AI 协作要求。
- `CONTRIBUTING.md`：所有成员适用的协作流程。
- `plan/`：当前产品计划及必要的跨任务协作计划。
- `docs/`：长期维护的项目知识、决策、指南和验证报告。
- `planning/`：历史 Word 计划与生成工具，不作为当前执行依据。
- `.github/`：Issue、Pull Request 模板及 CI 工作流。

本地构建产物、运行时数据、环境配置和密钥不纳入 Git。
