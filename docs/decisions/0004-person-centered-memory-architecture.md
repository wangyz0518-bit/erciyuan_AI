# ADR-0004（提议）：人物中心数据边界与记忆优先正式工程

- **状态：提议，待项目发起人在 #35 启动前确认；合并文档不等于接受**
- 日期：2026-11-18
- 提案范围：正式 Flutter 工程边界、人物时间线、离线三层记忆的实施先后
- 已接受前提：[ADR-0001 Flutter + Dart](0001-mobile-stack.md)、[ADR-0002 Android/iOS 首版](0002-three-platform-scope.md)
- 详述：[正式架构](../design/flutter-memory-first-architecture-20261118.md)、[数据契约](../design/person-memory-data-contract-20261118.md)
- 关联任务：[#34](https://github.com/wangyz0518-bit/erciyuan_AI/issues/34)、[#35](https://github.com/wangyz0518-bit/erciyuan_AI/issues/35)、[#36](https://github.com/wangyz0518-bit/erciyuan_AI/issues/36)、[#47](https://github.com/wangyz0518-bit/erciyuan_AI/issues/47)

## 背景

产品发起人确定：**一个人物只有一条持续存在的逻辑对话**，人物之间数据严格隔离，用户拥有并可导出原始历史与派生记忆。现有 `apps/mobile_poc/` 为已验证的 Flutter 本地 PoC，不包含完整人物中心记忆。多个未合并的网关和 UI PR 不能直接成为产品架构。

2026-11-18 又确认记忆优先开发顺序：#34 → #35 → #36 → #47 → #38 → #39，#31 暂缓。为了让 #47 可以在真实模型和正式 UI 尚未接通时验收，必须分离领域内核和外部供应商。

## 候选方案

1. **继续原地扩展 PoC，直接耦合模型网关**：代码上手快，但旧消息/状态模型与单机网关容易绑住长期数据结构，改动还可能破坏既有 PoC 测试。
2. **另建正式 Flutter 应用 + 原始记录优先 + 端口驱动记忆**：将 `apps/mobile_poc/` 保留为验证工程，`apps/mobile/` 按用途渐进创建，存储/摘要器/模型服务通过端口接入；可以先用确定性摘要器完成 #47。
3. **先建设生产后端、真实模型和全局记忆，再回填移动端**：与当前记忆优先、人物隔离和用户本地数据所有权冲突，产生未经验证的账号/多租户部署依赖。

## 建议决策（未生效）

推荐方案 **2**，具体约束：

- 业务实体以 `owner_id + character_id` 为隔离边界，`CharacterTimeline` 对同一人物唯一；后台归档片段和模型请求不属于用户可见聊天。
- 三层数据分为 **RawEvent 事实层**、**ArchiveSegment/MemorySummary 索引层**、**PersonaIdentityVersion 身份层**。归档与身份更新不修改/删除原始事实。
- 正式 Flutter 首版保留 PoC 并创建最小 `apps/mobile/`，采用模块化 feature 目录、构造函数注入、Flutter 轻量状态，不预先引入大型状态/DI 框架。
- SQLite 为本地优先事实层；来源引用和检索需始终限定到 owner/character。服务端真实身份认证方案在 #38 再确定。
- 先通过可替换的 Mock/确定性 Summarizer 完成 #47 离线内核，再在 #38/#39 引入生产服务/真实模型，实测 Token、缓存命中率、召回与成本。
- 导出机制从 #36 开始支持原始数据，#47 扩展到完整三层与来源引用，不以模型服务商私有格式作为唯一存档方式。

## 预期后果

**优点**：长期人物身份与模型 provider 解耦；原始数据可追溯、用户可携带；可以在离线状态可靠测试归档和索引；避免直接合并他人未完成的 PR。

**代价**：短期存在 PoC 与正式工程两个 Flutter 项目；需要显式模块接口和本地数据迁移工具；真实质量/缓存数据要等 #39，不能提前称作通过。

**风险控制**：按 Issue #35 逐步创建最小代码，不生成空抽象；#36 先实现原始事件与全量导出；#47 的摘要器为可替换验证工具；#38 才讨论多租户鉴权、安全部署和模型供应商。

## 决策门槛与回退

本文件保持**提议**状态。项目发起人在确认下一项 #35 的具体执行计划时，一并确定是否接受方案 2 或要求修改。若决定不同，先更新本 ADR 与 #35 计划，再动正式工程，不将提议悄悄转为“已接受”。

可回退路径：保留现有 PoC 和 main；各项新功能在独立分支增量实现，未合并代码不作为产品基础；导出格式保留版本号供后续迁移。

## 参考

- [人物中心原则](../design/person-centered-companion-principles-20261118.md)
- [三层记忆数据契约](../design/person-memory-data-contract-20261118.md)
- [#34 专项计划](../../plan/issue-34-memory-architecture-20261118.md)
