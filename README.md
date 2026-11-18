# 二次元 AI 陪伴软件 · erciyuan_AI

面向手机使用的 AI 陪伴产品，计划支持角色形象、声音和性格定制，以及文字、语音交流和简单表情表现。

## 已确认方向

- 首版平台：**Android、iOS**；原生鸿蒙后续适配，具体时间另行确定，见 [ADR-0002](docs/decisions/0002-three-platform-scope.md)。
- 首版移动端技术栈：**Flutter + Dart**，见 [ADR-0001](docs/decisions/0001-mobile-stack.md)。

项目当前实现情况以仓库代码、GitHub Issues 和 Pull Requests 为准；不在 README 中维护重复的任务状态台账。规划目标、PoC 结果和实际实现必须明确区分。

## 从这里开始

1. 阅读 [项目规则](AGENTS.md)，了解项目约束。
2. 阅读 [团队协作规则](CONTRIBUTING.md)，了解任务、分支和 PR 流程。
3. 阅读 [产品计划](plan/README.md)，了解产品目标、功能范围和阶段路线。
4. 阅读 [文档索引](docs/README.md)，查找调研、决策、指南和接口资料。

## 获取项目

克隆仓库后，按对应指南准备开发环境：

    git clone https://github.com/wangyz0518-bit/erciyuan_AI.git
    cd erciyuan_AI

项目开发环境与命令以对应指南及实际工程配置为准。Android 环境搭建记录见 [Windows 安卓开发环境搭建与验证](docs/guides/windows-android-setup-20261112.md)。

## 目录

- AGENTS.md：项目约束与 AI 协作要求。
- CONTRIBUTING.md：所有成员适用的协作流程。
- plan/：当前产品计划及必要的跨任务协作计划。
- docs/：长期维护的项目知识，详见 [文档索引](docs/README.md)。
- planning/：历史 Word 计划与生成工具，不作为当前执行依据。
- .github/：Issue 与 Pull Request 模板。

本地排版检查产物、环境配置和密钥不纳入 Git。
