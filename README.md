# 二次元 AI 陪伴软件 · erciyuan_AI

面向手机使用的 AI 陪伴产品，支持角色对话、动态形象、角色分享与社区交流。

**[项目进展报告（2026-11-25 · PDF）](docs/reports/project-status-20261125.pdf)**

前 3 页可以快速了解四个 App 入口、独立运营后台和用户能走通的流程。后 5 页记录实现细节、联调证据和待验收项。

**本轮进展**　用户可以纠正或忘记角色记忆，预览并绑定形象和音色，从社区发现与导入角色，通过回复通知回到原评论。在「我的」可以生成恢复码、备份和恢复本机数据或注销账户。独立运营后台可查看模型和语音服务的调用、失败、用量与估算费用。

Android 模拟器、网关和运营网页已在同一服务实例完成联调，并通过 `main` 复验，使用合成账户和模拟模型、语音服务。iOS 验收结果单列在报告第 7 页。[试用与验证说明](docs/guides/community.md) · [主线联调记录](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/45542096238)

## 已确认方向

- 首版平台：**Android、iOS**；原生鸿蒙后续适配，见 [ADR-0002](docs/decisions/0002-three-platform-scope.md)。
- 首版移动端技术栈：**Flutter + Dart**，见 [ADR-0001](docs/decisions/0001-mobile-stack.md)。

## 从这里开始

1. 阅读 [项目规则](AGENTS.md)，了解项目约束。
2. 阅读 [协作原则](CONTRIBUTING.md)，了解开放协作方式。
3. 阅读 [产品计划](plan/README.md)，了解产品目标和阶段路线。
4. 阅读 [文档索引](docs/README.md)，查找设计、决策、指南和验证报告。

## 移动端工程

正式 Flutter App 位于 [apps/mobile/](apps/mobile/README.md)，提供「陪伴、角色、社区、我的」四个入口。默认可离线体验，配置网关后支持在线文字、按住说话和连续通话。每个角色使用独立的 SQLite 时间线。

多用户账户、角色导入和独立运营网页由 [模型网关](services/model_gateway/README.md) 提供，试用和后台配置见 [社区与运营指南](docs/guides/community.md)。早期验证工程和历史记录见 [Flutter PoC](apps/mobile_poc/README.md) 与 [Android PoC 报告](docs/reports/android-poc-report-20261112.md)。

## 获取项目

```sh
git clone https://github.com/wangyz0518-bit/erciyuan_AI.git
cd erciyuan_AI
```

按 [正式 App 构建说明](apps/mobile/README.md) 安装 Flutter 和平台工具链，再进入 `apps/mobile/` 执行依赖安装、检查和构建。iPhone 安装见 [iOS 开发安装指南](docs/guides/ios-personal-team.md)。

## 目录

- `apps/mobile/`：正式 Android/iOS Flutter App。
- `apps/windows_conversation_lab/`：Windows 连续语音对照客户端。
- `services/model_gateway/`：模型与语音网关、社区账户和运营后台。
- `apps/mobile_poc/`：早期移动端验证工程。
- `AGENTS.md`：项目约束与 AI 协作要求。
- `CONTRIBUTING.md`：开放协作的基本原则。
- `plan/`：当前产品计划及必要的跨任务协作计划。
- `docs/`：长期维护的项目知识、决策、指南和验证报告。
- `planning/`：历史 Word 计划与生成工具，不作为当前执行依据。
- `.github/`：CI 工作流。

本地构建产物、运行时数据、环境配置和密钥不纳入 Git。
