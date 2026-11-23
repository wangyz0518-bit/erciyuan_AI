# 项目规则

本文件供 AI 编码助手与团队成员快速了解项目边界和必须遵守的约束。团队通用协作流程见 [CONTRIBUTING.md](CONTRIBUTING.md)，项目知识文档见 [docs/README.md](docs/README.md)。

## 项目

二次元 AI 陪伴 App，面向手机使用，计划支持角色形象、声音和性格定制，以及文字、语音交流和简单表情表现。

## 已确认决策

- 首版平台：Android、iOS；原生鸿蒙后续适配，见 [ADR-0002](docs/decisions/0002-three-platform-scope.md)。
- 首版移动端技术栈：Flutter + Dart，见 [ADR-0001](docs/decisions/0001-mobile-stack.md)。
- 已确认决策以 `docs/decisions/` 中的 ADR 为准；提案和调研结论不自动构成决策。

## 当前工程

- 正式 Flutter App 位于 `apps/mobile/`。配置声音网关后使用 Windows 测试版确定的 v3 会话，支持文字、按住说话、连续通话、插话和每轮延迟。每个角色沿用正式 App 的 SQLite 时间线。
- 新增角色按[正式 App 角色接入与验收](docs/guides/character-onboarding.md)核对人设、会话、形象素材、取景与缩放。
- Windows 对照客户端位于 `apps/windows_conversation_lab/`，共用 `services/model_gateway/`。仅在服务端配置供应商凭据。入口见 [Windows 指南](docs/guides/windows-conversation-20261118.md)、[iPhone 安装指南](docs/guides/ios-personal-team.md) 和 [v3 会话契约](docs/接口/model-gateway-conversation-v3.md)。
- 独立 Flutter PoC 位于 `apps/mobile_poc/`。模拟器、合成语音和真人外放验收分别记录。

## 协作

项目采用开放式协作，团队共同原则见 [CONTRIBUTING.md](CONTRIBUTING.md)。不规定个人 PR 权限或审批方式。

## 安全与数据

- 不提交密钥、令牌、`.env`、真实聊天记录、私人录音和未经确认的个人资料。
- 示例配置只使用占位值；密钥由服务端持有，客户端不打包。
- 日志和截图中的个人信息、密钥、内网地址需脱敏。

## 禁止

- 重大公共接口或核心数据模型变更，先与相关参与者沟通。
- 把规划目标、模拟结果标成已完成。
- 用 `git push --force` 覆盖公共分支历史。
- 大规模改写无关文档，或提交大量排版产物。
