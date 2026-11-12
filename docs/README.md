# 文档索引

本目录按“状态、流程、知识、过程、操作”组织。新增文档时先更新所在目录的 `README.md`，再更新本索引。

## 入口

| 文档 | 用途 | 更新时机 |
| --- | --- | --- |
| [state.md](state.md) | 当前阶段、待办、风险、下一步 | 每周或阶段变化时 |
| [process/](process/README.md) | 团队安排、协作流程、文档规范 | 按需 |
| [research/](research/README.md) | 调研、选型、技术评估 | 按需 |
| [decisions/](decisions/README.md) | 架构与选型决策记录 | 每次决策 |
| [guides/](guides/README.md) | 配置、开发、排障，含 [Windows 安卓开发环境搭建与验证](guides/windows-android-setup-20261112.md) | 按需 |
| [reports/](reports/README.md) | 实际验证结果、问题与证据边界，含 [沉浸聊天验收](reports/immersive-chat-flutter-20261112.md) | 每轮验证后 |
| [接口/](接口/README.md) | 接口契约草案（暂缓整理） | 接口变更时 |

## 约定

- 每份文档开头写状态头，格式见 [process/documentation.md](process/documentation.md)。
- 调研报告只陈述事实、选项和证据，不写“已决定”。
- 最终选择写入 `decisions/`，并在调研报告中链接对应 ADR。
- 过期文档移到 `archive/`，不直接删除。

## 待建

| 目录 / 文件 | 建立时机 |
| --- | --- |
| `architecture.md` | 技术栈确定后 |
| `api/` | 接口进入实现阶段，从 `接口/` 迁入 |
| `archive/` | 出现第一份过期文档时 |
