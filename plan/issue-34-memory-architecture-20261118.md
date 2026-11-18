# Issue #34：人物中心正式工程架构设计执行清单

> 日期：2026-11-18
> 状态：#34 已完成（历史设计清单）
> Issue：[正式 Flutter 工程架构设计 #34](https://github.com/wangyz0518-bit/erciyuan_AI/issues/34)
> 主线：#34 → #35 → #36 → #47 → #38 → #39；#31 暂缓

## 1. 输入与原则

- 已接受技术决策：[Flutter + Dart](../docs/decisions/0001-mobile-stack.md)、[Android/iOS 首版](../docs/decisions/0002-three-platform-scope.md)。
- 已确认产品原则：[人物中心持续陪伴](../docs/design/person-centered-companion-principles-20261118.md)：一个人物一条逻辑时间线、三层记忆、隔离、一键全量导出。
- 当前正式代码基线为 `apps/mobile_poc/` 本地 Flutter PoC，不是长期生产实现。
- PR #15～#24 是相关历史设计与实现参考，复用时检查来源、依赖及兼容性。
- PR #32/#49 与 #31 模拟器 CI 相关，不属于本 Issue 范围。

## 2. 本 Issue 的子任务

| 子任务 | 交付物 | 检查方法 |
|---|---|---|
| A1 PoC 与相关 PR 审计 | [正式架构文档](../docs/design/flutter-memory-first-architecture-20261118.md) 的现状、复用与边界 | 对照现有文件路径和 PR，明确已合并/未合并 |
| A2 正式 Flutter 结构 | 架构文档的目录、依赖方向、状态/导航/DI 方案 | 不与 ADR-0001/0002 冲突，无循环依赖 |
| A3 三层记忆数据契约 | [记忆与数据契约](../docs/design/person-memory-data-contract-20261118.md) 的实体、存储和事件语义 | 每人物唯一时间线、来源引用与隔离可推导 |
| A4 归档/召回/身份更新 | 数据契约中的时序、失败/重试与校验 | 归档可幂等、原始事件不丢失、身份更新有边界 |
| A5 用户数据所有权 | 导出格式版本、完整性、删除与迁移边界 | 原始记录和派生三层数据均可导出 |
| A6 稳定 Prompt 缓存 | 规范化前缀、动态区与测量指标 | 避免虚称无限 Token、供应商缓存命中率 |
| A7 ADR 与迁移 | [ADR-0004 提案](../docs/decisions/0004-person-centered-memory-architecture.md)、#35～#39 依赖矩阵 | 不把提议标成已接受，清楚交付界限 |
| A8 文档检查、自审 | 路径/链接、关键约束检查，PR 自审记录 | 只做文档与设计、无 Flutter 功能变更 |

## 3. 验收边界

完成 #34 指**提交并自审完备的设计方案、明确的架构选择与待批准 ADR 提案**，不代表生产数据层、三层记忆引擎、真实模型或缓存测量已经实现。

不在此 Issue 决定模型供应商、部署平台、语音/Live2D 技术选型或账户云同步策略。这些必须在后续 #38、#39、#42～#44 中验证并决策。

## 4. 后续工作

#34 的设计为 [#35 最小正式 Flutter 工程](https://github.com/wangyz0518-bit/erciyuan_AI/issues/35) 提供基础；进度以实际 Issue/PR 为准。
