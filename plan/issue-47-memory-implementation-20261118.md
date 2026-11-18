# Issue #47：离线三层记忆内核实施记录

> 状态：#47 独立 PR 开发中；**Flutter CI、源码格式、真实设备和真实模型结果以实际 GitHub Actions 为准，尚未宣称通过**
> 基线：main f1749f04eb0647adcc66288d0ce7aba82b40559d，已有 #35 Flutter 工程及 #36 SQLite 事实层
> 范围：人物中心、供应商无关、可离线验证的原始记录→摘要索引→版本身份

## 实际实施

- 在原 PersonDatabase schema v2 上迁移到 v3；不改变旧 PoC。新增 archive_segments、memory_summaries、summary_sources、memory_terms、archive_cursors、persona_identity_versions、identity_candidates；所有表使用 owner+character 复合外键。
- 注入可替换 MemorySummarizer；默认 DeterministicSummarizer 对**已完成**原始事件产生稳定摘要、关键词和精确 sourceEventIds。这是规则性整理而非真实 LLM 语义总结。可通过 PersonDatabase.open(automaticSummarizer: ...) 选择事件提交后自动归档，或 memory.archiveReady() 进行有界恢复/补偿；默认不在既有 #36 调用中启用。
- 先在事务外生成摘要，事务内重新核查原始数据摘要 digest 和归档游标；写入片段、摘要、引用、索引、游标为一个事务。相同来源的重复请求不生成第二条相同摘要；失败时游标不前进；摘要不删除原文。
- 搜索只返回相同人物的 active 摘要。可通过 summaryId 回查同一 owner+character 的原文；ContextAssembler 读取人物基础身份与已批准身份版本，在稳定前缀后装配近期已完成原文、相关摘要和可选来源回查。字符数是离线代理指标，不是 Token/Prompt Cache 真实数据。
- IdentityCandidate 必须有本人物有效摘要来源才能提出；禁止使用和用户基础设定同名的字段；只能由显式 approveIdentity(...) 产生新身份版本。拒绝/候选/已批准版本可以查询，归档永不自动修改核心设定。
- 对完整修正事件 revisionOf，原子失效依赖旧来源的摘要、索引和候选，并回退相应摘要器游标；历史原始事实仍保留。对用户显式隐私遮盖 redactEvent，原子擦除该原文内容、失效并清空派生的敏感摘要/身份内容。
- 数据导出在 SQLite 同一读事务中包含原始事件、人物、生成任务、归档游标/片段、摘要/关键词/原始来源、身份候选和版本；attachments 仍为空占位，尚未建立正式附件持久化或跨端文件分享入口。

## 核心文件与复用来源

| 文件 | 内容 |
| --- | --- |
| apps/mobile/lib/features/memory/domain/memory_models.dart | MemorySummarizer、DeterministicSummarizer、Context 等供应商无关结构 |
| apps/mobile/lib/features/memory/data/person_memory_repository.dart | schema v3、幂等归档与检索、身份审核、上下文装配 |
| apps/mobile/lib/features/timeline/data/person_database.dart | v2→v3 迁移、事实修改失效钩子、可选自动归档、全量导出 |
| apps/mobile/test/person_memory_test.dart | 人物/owner 隔离、来源/重启、纠错/隐私、身份审批和自动归档负向测试 |
| main apps/mobile/lib/features/timeline/ | 复用 #36 SQLite/raw fact，不复制 PoC 消息 schema |
| 所有者 PR #16/#21/#22/#24 | 只读参考角色隔离、request_id、超时/取消及任务幂等经验；未合并或修改他人 PR |

## 执行与验收矩阵

在 Flutter 3.50.0 及 Dart 3.14 环境：

```bash
cd apps/mobile
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

应核验：
1. schema v1→v3 与 v2→v3 迁移保留时间线、人物和原始事件。
2. 相同来源重试无重复摘要；摘要来源伪造/异常时事务不部分提交。
3. 不同 owner、不同人物之间检索、来源回查、导出与身份版本不串数据。
4. 用户确认身份前稳定前缀不变化；拒绝基础身份覆盖。
5. 修正后旧摘要失效，游标安全回退且可重新归档；明确隐私遮盖后导出不残留原敏感正文。
6. 近期原文不包含失败/取消事件，按需展开摘要来源；稳定身份前缀与动态内容解耦。
7. GitHub Actions analyze/test/Android Debug APK 的真实执行结果。

**未验收的范围**：实际模型记忆质量、真实语义召回/embedding、Prompt Cache 命中率、供应商 Token 成本、正式前端记忆管理 UI、iOS 运行与真机。分别由 #39、#37、#40/#41 等后续任务验证；不能将规则摘要称作真实智能记忆。

## 已知设计取舍

- 规则摘要无自然语言理解能力，来源可追溯但质量不等同于模型摘要；可在后续用不同 version 的 Summarizer 重新处理原始记录。
- 归档触发采用可配置完整事件数阈值，适于离线可靠性测试；更复杂的语义边界/后台调度和性能优化可按真实设备数据迭代。
- #36 原始事件中存在 revision_of 字段；本实现对完成的修正事件排除旧事实的**当前上下文**，保留旧事实用于完整历史审计。
- 真实 Token 限额、召回排序质量与提供商缓存指标仍需 #39 实测。
