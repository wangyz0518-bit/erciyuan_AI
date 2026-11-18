# 人物中心三层记忆：数据契约与离线引擎设计 v0

> 状态：Issue #34 设计草案 / 可测试契约，不是已实现的正式数据库或公开服务 API
> 日期：2026-11-18
> 关联：[总体架构](flutter-memory-first-architecture-20261118.md)、[人物中心产品原则](person-centered-companion-principles-20261118.md)、[ADR-0004 提议](../decisions/0004-person-centered-memory-architecture.md)
> 后续实现：#36 原始记录与导出 → #47 离线三层记忆 → #38/#39 真实模型验证

## 1. 不变量与名词

- **逻辑边界 = owner_id + character_id**。一个 owner 可以拥有 N 个人物，一个人物只拥有一条用户可见的持续对话时间线。
- `timeline_id` 是这一条逻辑时间线的内部稳定标识，不能随模型窗口、归档片段、请求重试变化。
- RawEvent 记录可追溯的原始互动。**归档不是删除**，是额外保存 ArchiveSegment 与 Summary 的操作。
- MemorySummary 的来源必须能回查原始事件；没有来源的推断不得写入已确认的人物身份。
- PersonaIdentity 分离「用户明确设定的基础身份」和「带来源/版本的动态归纳」；模型猜测必须保持候选态。
- 一键导出应覆盖 owner 的**全部人物**，包含完整原始时间线、身份、归档、摘要、来源引用和已拥有的附件；尚无数据的层显式空数组。
- `request_id`、`provider_session_id`、`archive_id` 都不是可见会话 ID。任何 App UI 不提供同一人物下的“新建会话”。

## 2. 数据实体契约

| 实体 | 唯一标识与关系 | 最小字段 / 语义 |
|---|---|---|
| DataOwner | `owner_id`（本机安装 scope；服务端账户后续映射） | `created_at`, `schema_version`；本地 ID 不等于在线鉴权 |
| Character | `(owner_id, character_id)` | `name`, `created_at`, `identity_version` |
| CharacterTimeline | `(owner_id, character_id)` 上唯一 | `timeline_id`（不可因归档变化）、`next_sequence` |
| RawEvent | `(owner_id, character_id, event_id)` | `sequence`, `occurred_at`, `speaker`, `kind`, `content`, `request_id`, `provenance`, `revision_of` |
| GenerationTask | `(owner_id, character_id, request_id)` | `state`, `provider_task_ref`, `retry_of`, `started_at`；与 raw events 独立 |
| ArchiveSegment | `(owner_id, character_id, archive_id)` | `sequence_from/to`, `source_digest`, `generator_version`, `status` |
| MemorySummary | `(owner_id, character_id, summary_id)` | `archive_id`, `summary`, `topics`, `confidence`, `generator_version`, `created_at`, `status` |
| SummarySource | `(owner_id, character_id, summary_id, event_id)` | 同一人物原始事件的强引用，不可跨 scope |
| MemoryTerm | `(owner_id, character_id, term, summary_id)` | 主题/关键词的可查索引，不等于语义向量索引 |
| PersonaIdentityVersion | `(owner_id, character_id, version)` | `base_identity`, `stable_state`, `source_summary_ids`, `approved_by`, `created_at` |
| IdentityCandidate | `(owner_id, character_id, candidate_id)` | `proposed_change`, `source_summary_ids`, `confidence`, `state=proposed|approved|rejected` |
| ArchiveCursor | `(owner_id, character_id, summarizer_version)` | `last_committed_sequence`；**只能随同源摘要成功事务提交前进** |

### 2.1 版本/时间约定

- 事件和归档使用稳定的字符串 ID（UUID/ULID 或等价机制；#36 实现时确定格式），不依赖全局递增自增 ID 作为服务端契约。
- 同一人物时间线追加采用事务性 `sequence` 单调增长；不同人物之间不要求共享序号。
- 时间使用 ISO 8601 UTC 并明确时区；展示时才转换本地时区。原始顺序以 `sequence` 为准，不能单独靠时间戳。
- `schema_version`、`prompt_template_version`、`summarizer_version`、`persona_version` 独立演化；模型切换不会把原始事件迁移成另一个人物。
- 原始事件的修正通过 `revision_of` 追加更正事件；明确用户删除可以删除/脱敏目标原始内容，但必须同步失效所有依赖摘要和索引，不能留下无法解释的幻影记忆。

## 3. SQLite 建议结构（设计伪 DDL）

以下是要在 #36 具体实现、验证和迁移的**关系约束草图**，不是可以直接运行的完整 schema。所有涉及人物的表都必须包含 owner + character 的复合主键或外键，并打开 SQLite 外键检查。

```sql
PRAGMA foreign_keys = ON;

CREATE TABLE characters (
  owner_id TEXT NOT NULL,
  character_id TEXT NOT NULL,
  base_identity_json TEXT NOT NULL,
  name TEXT NOT NULL,
  PRIMARY KEY (owner_id, character_id)
);

CREATE TABLE character_timelines (
  owner_id TEXT NOT NULL,
  character_id TEXT NOT NULL,
  timeline_id TEXT NOT NULL UNIQUE,
  next_sequence INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (owner_id, character_id),
  FOREIGN KEY (owner_id, character_id)
    REFERENCES characters(owner_id, character_id)
);

CREATE TABLE raw_events (
  owner_id TEXT NOT NULL,
  character_id TEXT NOT NULL,
  event_id TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  occurred_at_utc TEXT NOT NULL,
  speaker TEXT NOT NULL,
  kind TEXT NOT NULL,
  content_json TEXT NOT NULL,
  request_id TEXT,
  revision_of TEXT,
  PRIMARY KEY (owner_id, character_id, event_id),
  UNIQUE (owner_id, character_id, sequence),
  FOREIGN KEY (owner_id, character_id)
    REFERENCES character_timelines(owner_id, character_id),
  FOREIGN KEY (owner_id, character_id, revision_of)
    REFERENCES raw_events(owner_id, character_id, event_id)
);

CREATE TABLE archive_segments (
  owner_id TEXT NOT NULL,
  character_id TEXT NOT NULL,
  archive_id TEXT NOT NULL,
  sequence_from INTEGER NOT NULL,
  sequence_to INTEGER NOT NULL,
  generator_version TEXT NOT NULL,
  source_digest TEXT NOT NULL,
  PRIMARY KEY (owner_id, character_id, archive_id),
  UNIQUE (owner_id, character_id, sequence_from, sequence_to,
          generator_version, source_digest),
  FOREIGN KEY (owner_id, character_id)
    REFERENCES character_timelines(owner_id, character_id),
  CHECK (sequence_to >= sequence_from)
);

CREATE TABLE memory_summaries (
  owner_id TEXT NOT NULL,
  character_id TEXT NOT NULL,
  summary_id TEXT NOT NULL,
  archive_id TEXT NOT NULL,
  summary TEXT NOT NULL,
  status TEXT NOT NULL,
  PRIMARY KEY (owner_id, character_id, summary_id),
  FOREIGN KEY (owner_id, character_id, archive_id)
    REFERENCES archive_segments(owner_id, character_id, archive_id)
);

CREATE TABLE summary_sources (
  owner_id TEXT NOT NULL,
  character_id TEXT NOT NULL,
  summary_id TEXT NOT NULL,
  event_id TEXT NOT NULL,
  PRIMARY KEY (owner_id, character_id, summary_id, event_id),
  FOREIGN KEY (owner_id, character_id, summary_id)
    REFERENCES memory_summaries(owner_id, character_id, summary_id),
  FOREIGN KEY (owner_id, character_id, event_id)
    REFERENCES raw_events(owner_id, character_id, event_id)
);
```

`IdentityVersion`、`IdentityCandidate`、`ArchiveCursor`、`GenerationTask` 和 `MemoryTerm` 表同样要求复合所有权外键、唯一约束、版本和生命周期规则；具体迁移和索引使用 #36/#47 的独立设计/测试完善。特别是 SQLite `UNIQUE` 对 NULL 的处理、`revision_of` 可选外键与实体软删除语义需在实现中专门验证。

### 3.1 为什么不能沿用 PoC `messages` 表作正式记忆表

当前 `apps/mobile_poc/lib/data.dart` 是 `id INTEGER PRIMARY KEY` + `character_id` + `status` + `reply_to` 的简单消息表，并且在 `save(..., conflictAlgorithm.replace)` 中可替换旧行。正式 RawEvent 要求：
- owner/character 隔离及外键约束；
- 保留完整原始事实和可追溯的编辑历史；
- 来源引用能跨归档稳定定位事件；
- pending/failed 的生成中间态与最终 RawEvent 分离。

因此**选择性迁移行为和测试，不直接把 PoC schema v1 当正式数据模型**。数据升级必须在 #36 保留旧 PoC 数据的可恢复路径（如需要迁移则有导入工具），不直接修改/破坏用户既有 PoC 数据库。

## 4. 核心端口和数据流

### 4.1 不依赖服务商的领域接口（示意）

```text
CharacterRepository:
  get(owner, character)
  list(owner)
  updateBaseIdentity(owner, character, expectedVersion, changes)

TimelineRepository:
  appendFinalEvent(owner, character, event, idempotencyKey)
  readRecent(owner, character, limit)
  readRange(owner, character, sequenceFrom, sequenceTo)
  readByIds(owner, character, eventIds)

ArchiveRepository:
  readCursor(owner, character, generatorVersion)
  commitSegmentAndSummary(owner, character, segment, summary, sources,
                          expectedCursor, nextCursor)  # 单事务
  lookupSummary(owner, character, summaryId)
  searchIndex(owner, character, query, limit)

Summarizer:
  summarize(characterIdentity, sourceEvents, algorithmVersion) -> DraftSummary

IdentityUpdatePolicy:
  propose(baseIdentity, currentDynamicState, memoryEvidence) -> Candidate[]
  applyApproved(owner, character, candidateId, expectedIdentityVersion)

ContextAssembler:
  build(owner, character, currentInput, tokenBudget) -> ContextBundle
  # stablePrefix, selectedSummaries, recentEvents, expandedSourceEvents, citations

DataExportService:
  exportAll(owner, outputSink) -> ExportManifest
  # 事务一致性 + 数据引用完整性
```

- 所有端口都必须显式接受/携带 `owner_id` 和 `character_id`，不能依赖 UI 当前选中人物这个可变全局变量。
- 应用层建立一次 `CharacterScope` 并用于仓储/检索/缓存/请求身份；服务端收到请求后要从已认证主体推导 owner，不能信任客户端自己填的 owner ID。
- MockSummarizer 可以使用稳定的规则生成可追溯合成摘要（不宣称语义质量），使 #47 在不接入真实 LLM 的情况下可被完整自动测试。
- 真实模型 Adapter 在 #39 才接入，必须能替换 Summarizer 而不改变 RawEvent 或 Export 格式。

### 4.2 归档状态机

```text
UNARCHIVED → SNAPSHOT_TAKEN → SUMMARY_DRAFTED → VALIDATED
                                          ↘ FAILED_RETRYABLE
VALIDATED → TRANSACTION_COMMIT(summary, sources, index, cursor) → ARCHIVED
```

1. 只从**已最终提交**的事件按人物/时间线固定一段范围，并记录首尾 sequence 与 source_digest。
2. 计算幂等身份：`owner + character + range + generator_version + source_digest`，同一输入重试返回同一完成结果，不复制 summary。
3. 摘要器运行在数据库事务外；提交前重新检查原始事件范围/摘要来源是否仍匹配，防止同时编辑/删除产生过时摘要。
4. 在同一个 SQLite 事务中写归档、摘要、来源、索引和 ArchiveCursor；失败整体回滚，原始数据仍可再次归档。
5. 重建索引或改换摘要器应以新版本生成派生数据，旧版本可标为 superseded；不可删除原始事件。
6. 若归档中途发生用户明确删除，原始范围版本变化时旧草稿不可提交，已依赖该记录的摘要需标记 invalidated 并重新构建。
7. 归档完成后也不自动把摘要内容升级为人物基础身份。

### 4.3 检索与原始回查

- 查询仅作用于当前 owner + character 的索引，不跨人物搜索。
- 初版 #47 采用确定性的关键字/主题匹配及时间信息排序，必要时允许固定容量的穷举检索；向量召回是后续选项，不阻塞离线内核。
- `MemorySummary` 需要 summary_id、sourceEventIds、片段时间范围、生成版本、状态；缺失/无效的引用不返回为可信事实。
- 当前用户问题需要具体原话、时间或高风险结论时，`ContextAssembler` 根据 sourceEventIds 只回查同一人物 RawEvent；回查失败则标记证据不足，不能填入臆测原话。
- 近期未归档消息直接来自 RawEvent，不通过摘要代替；上下文超出模型 tokenBudget 时按策略裁剪动态片段，**绝不能改写/删除数据库事实层**。

## 5. 人物身份与长期状态

### 5.1 两类可变性

- 基础身份：创作者/用户的明确设定。版本更新需用户操作或明确确认，不接受后台摘要静默覆盖。
- 动态身份：经证据支持的关系变化、长期已确认偏好与稳定状态；每次版本记录 source_summary_ids/source_event_ids、修改者或策略、置信度、时间和父版本。
- 推断候选：尚未通过验证/确认的模型猜测。需要明确的 `proposed` 状态，默认不直接加载为稳定事实。
- 临时情绪和本轮上下文不属于长期身份；应留在近期原始对话和动态检索片段。
- 对敏感个人信息采取最小化处理：未经用户授权，不从原文自动固化到跨轮持久人物身份。

### 5.2 更新并发与回滚

使用 `expectedIdentityVersion` CAS（比较并交换）；版本冲突拒绝/重试，不静默覆盖用户编辑。每次已确认更新保存不可变版本快照和来源；用户可以查看来源、撤回候选和通过显式操作恢复历史版本。删除影响来源事件时须撤销/重新评估关联状态。

## 6. 稳定上下文、Prompt Cache 与预算

```text
[System policy + template_version]
[Character identity + approved stable state + persona_version]  # 稳定、可缓存前缀
[相关摘要及可回查的来源引用]                              # 动态
[近期未归档原始事件]                                     # 动态
[必要时展开的历史原始事件]                               # 动态
[当前用户输入与工具结果]                                 # 动态
```

- 同一 `owner_id, character_id, model_id, template_version, persona_version` 的前缀必须逐字节确定性。固定字段顺序、换行、转义、Unicode 规范和缺省值表达，时间戳/随机 ID 不放稳定区。
- 任何角色/版本/模型变更都产生不同逻辑缓存域，不能把人物 A 的摘要、身份或服务端缓存返回给人物 B。
- 动态检索内容放在身份前缀之后，内容按相关性和确定性 tie-break 排序，便于复现。
- 先离线验证输入内容长度和稳定前缀相等性；模型上下文窗口、费用、缓存命中率必须在 #39 使用真实 provider 计量。
- 记忆归档优化的不是无限 Token，而是用户体验上的长时连续性；长期归档不丢失原始证据。

## 7. 用户数据导出格式 v0 草案

推荐打包文件：

```text
erciyuan-export-v0.zip
  manifest.json                  # format、schema_version、owner、exported_at、checksums
  characters.json                # 该 owner 的全部人物，含当前资料
  events/<character_id>.jsonl    # 每个人物全部原始互动事件（序号有序）
  archives/<character_id>.jsonl  # 归档片段与版本
  summaries/<character_id>.jsonl # 摘要、topic 与来源 event_id
  identities/<character_id>.jsonl# 基础身份及所有动态版本/候选状态
  attachments/                   # 已拥有、获授权导出的媒体资源
```

- 导出使用可版本化、公开可读的 JSON/JSONL；媒体文件及 manifest 校验和独立存放。**具体 ZIP 打包、迁移器与加密方案在实现任务评审**，不能以此草案声称已完成一键导出。
- 事务读取快照覆盖所有人物与三层数据；清单包含每个文件的相对路径、字节数、校验和，拒绝路径穿越和任意绝对路径。
- 原始事件、摘要、身份均包含稳定 ID 和来源版本，复原不依赖某一家模型的专有缓存/Session ID。
- 用户可完全导出，包括不同人物的独立资料；不只是“最近一个聊天页面”。
- 未产生的记忆层以空文件/明确状态表示，不声称用户有不存在的记忆。
- 用户显式删除原始内容时，导出必须遵循实际删除结果，失效依赖摘要；不能为了历史归档把已要求删除的数据重新导出。
- 历史聊天、私人录音和访问令牌都不得出现在 CI 日志或仓库测试示例；真实生产导出需要适当的设备授权和用户操作确认。

## 8. 可靠性、隔离与安全测试矩阵

| 用例 | 测试输入 | 必须行为 |
|---|---|---|
| 每人物唯一时间线 | 同 owner 同人物重复创建 | 返回同一 timeline / 唯一约束拒绝重复 |
| 跨人物读与引证 | owner A / 人物 1 的摘要引用人物 2 event_id | 拒绝，不能被标为有效摘要 |
| 跨用户读 | owner A 读取 owner B 的人物 ID | 空或拒绝；不得从缓存旁路 |
| 原始事件幂等 | 同一 request_id 重试写入 | 不多插一条原始事件 |
| 分段并发 | 两个 worker 归档同范围 | 最多一个有效摘要/水位；完整可重试 |
| 归档中断 | 摘要生成后、数据库提交前崩溃 | RawEvent 原样保留；水位未前进 |
| 部分写入 | SummarySource 外键校验失败 | 整个摘要和 cursor 回滚 |
| 撤销编辑/删除 | 原文已被明确修改或删除 | 失效依赖 summary/identity，停止把旧内容当事实 |
| 身份版本竞争 | 两个不同身份候选同一 expectedVersion | 一个成功，另一个版本冲突 |
| 前缀稳定性 | 同 persona_version 连续两次序列化 | 字节完全相同 |
| 前缀隔离性 | 切人物或版本变化 | 缓存域/前缀区分 |
| 原始回查 | 摘要指向具体事实，问原话 | 只返回原人物有来源的记录；缺失明确 |
| 一键导出 | 2 owners × 每 owner 2 人物 | 仅导出所选 owner 的所有人物，引用完整且可读 |
| 模型未接通 | 只提供 MockSummarizer | #47 仍可运行、测试与导出；不宣称真实缓存命中 |
| 真实缓存指标 | #39 实际模型 provider | 有可核查的 Token/延迟/命中率/成本样本，不伪造 |

## 9. 交付顺序与未决项

- **#34**（当前）：只交付设计/契约/ADR 提议和审核记录。
- **#35**：最小正式 Flutter 工程，明确应用入口与测试；具体状态管理依必要性实施。
- **#36**：SQLite RawEvent/唯一时间线、事务、迁移、当前数据一键导出。
- **#47**：离线可运行 Summarizer、归档/索引、身份变更审核、ContextAssembler、三层导出；单元/故障测试。
- **#38**：真实服务/鉴权/多租户数据归属、端口契约及供应商评估。
- **#39**：真实 LLM、召回效果、流式请求、Token/成本、Prompt Cache；正式 UI #37 后续接入。

暂不定案：精确归档水位和 chunk 大小、分词/向量方案、摘要模型、供应商实际缓存机制、同步拓扑、生产加密与跨设备数据恢复。这些需以后续真实测试证据和用户确认确定。

## 10. 参考与可测试示例

- [全人物数据导出合成示例 v0](examples/person-memory-export-fixture-v0.json)：完全合成；用于校验数据层次和来源引用，不代表实际产品已生成该数据。
- [架构与模块边界](flutter-memory-first-architecture-20261118.md)
- [人物中心产品原则](person-centered-companion-principles-20261118.md)
- [PoC 数据层](../../apps/mobile_poc/lib/data.dart)
- [Issue #47](https://github.com/wangyz0518-bit/erciyuan_AI/issues/47)
