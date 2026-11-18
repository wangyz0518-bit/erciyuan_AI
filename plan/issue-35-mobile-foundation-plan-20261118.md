# Issue #35：最小正式 Flutter 工程基础建设——已批准的执行计划

> 状态：**ADR-0004 与本计划已获批准；等待剩余任务批量计划统一审阅，尚未实施 #35**
> 日期：2026-11-18
> 前置：[#34 人物中心架构](https://github.com/wangyz0518-bit/erciyuan_AI/issues/34) 已完成（[PR #50](https://github.com/wangyz0518-bit/erciyuan_AI/pull/50)）
> 决策门槛：[ADR-0004 提议](../docs/decisions/0004-person-centered-memory-architecture.md) 需与本计划一并由项目发起人确认
> 记忆优先顺序：#34（完成）→ **#35（待批准）** → #36 → #47 → #38 → #39
> PR 权限：仅修改、审核、合并执行账号 `keeyangyy` 的 PR；`wangyz0518-bit` 的 #15～#24 仅只读参考。

## 1. 已批准的架构选择

2026-11-18 用户已**接受 ADR-0004 的方案 2**：

- 保留 `apps/mobile_poc/`，现有 PoC、测试和历史报告继续可用；
- 独立建立正式 Flutter App：`apps/mobile/`；
- 先做可运行的最小应用入口和可测试的业务边界，不复制整个 PoC 和未合并 PR；
- 记忆三层数据与后端模型依赖通过领域端口隔离，#47 先使用确定性/Mock 摘要器实现并离线测试；
- 不在本阶段决定生产 LLM、语音/Live2D、账户与云同步。

**项目发起人要求将剩余 Issue 统一列出审核，见[批量执行计划](remaining-issues-batch-execution-20261118.md)。在该计划获批前不启动代码。**

## 2. 此 Issue 的明确范围

### 2.1 正式 Flutter 应用

1. 根据 ADR-0001/0002 建立 Flutter + Dart 正式工程，优先使用当前 PoC/CI 的 Flutter 3.50.0、Java 17 版本作为兼容基线。
2. `apps/mobile/` 包含 Android/iOS 模板、`pubspec.yaml`、锁文件、分析配置和最小可启动应用。
3. 保留 `apps/mobile_poc/` 全部已有数据、功能和测试，绝不原地覆写 PoC。
4. 基于 #34 文档创建**实际使用到的**模块边界：`app/`、人物 scope（owner+character）、minimal application state、基础导航与必要的数据/模型端口；不批量创建空文件或尚无调用方的框架。
5. 使用构造函数依赖注入、Flutter 内置 `ChangeNotifier` / `ValueNotifier` 或同等轻量原语。UI 限于能验证人物主页→单一持续对话占位页、切换人物和返回的最小流程。
6. Mock 组件必须明确标记模拟。当前阶段无真实 LLM 回复、长期记忆摘要、生产数据或导出文件。

### 2.2 基础测试和 CI

1. 增加最小单元测试：人物 scope 传递、两人物切换后的状态隔离、依赖注入与路由行为。
2. 增加最小 Widget 测试：应用能启动、进入当前人物唯一逻辑对话入口、人物切换不复用错误 scope。
3. 新增正式工程的快速 CI（如 `.github/workflows/flutter-mobile.yml`），触发条件限于 `apps/mobile/**` 与该 workflow，执行 Flutter 依赖安装、`dart format`、`flutter analyze`、`flutter test`、Android Debug APK 构建。
4. **不改写 #31 的模拟器集成 CI 工作流，不重启 PR #32、#49，也不在 #35 中运行 15 分钟 soak test。**
5. iOS 工程模板可生成并检查配置，但 macOS/Xcode 构建由 [#40](https://github.com/wangyz0518-bit/erciyuan_AI/issues/40) 单独验收；不能凭模板存在宣称 iOS 可构建。
6. 发布文档需标明 Flutter/Dart/Java 版本、复现命令和所有未验证项。

## 3. 可复用资产与处理约束

| 资产 | 用途 | 复用方式 |
|---|---|---|
| main 的 `apps/mobile_poc/` | Flutter 3.50.0、Android/iOS 模板、CI 及测试环境 | 只提取经过审查的配置和测试思路，保留 PoC 原状 |
| [PR #16](https://github.com/wangyz0518-bit/erciyuan_AI/pull/16) | Flutter 路由/人物场景/状态组件与生命周期 | 只读参考，后续 #37 按需选择性移植 |
| [PR #17](https://github.com/wangyz0518-bit/erciyuan_AI/pull/17) | Avatar 插件与资源包契约 | #44 参考，本 Issue 不引入 Live2D SDK |
| [PR #21](https://github.com/wangyz0518-bit/erciyuan_AI/pull/21)、[#22](https://github.com/wangyz0518-bit/erciyuan_AI/pull/22) | 模型请求 ID、事件流、取消/重试接口 | 仅借鉴端口约束；#38/#39 后续处理 |
| [PR #50](https://github.com/wangyz0518-bit/erciyuan_AI/pull/50) | 已合并的架构、数据契约、测试矩阵 | 作为正式工程设计输入 |

上述 #16/#17/#21/#22 均属于 `wangyz0518-bit`，不得直接改动、合并或关闭其 PR/分支。

## 4. 推荐的实现步骤

1. 在用户批准批量执行总计划后，从最新 main 建立 `feat/mobile-foundation`。
2. 建立 `apps/mobile/` 正式 Flutter 模板、依赖与最小启动入口。
3. 按实际调用关系增加人物 scope、应用状态和唯一时间线的基础导航，用纯内存 Mock 保证可测试。
4. 保持跨人物隔离的请求边界，避免形成会话列表或“新建会话”。
5. 新增单元/Widget 测试和正式工程快速 CI。
6. 更新正式工程 README、启动命令、未验证平台与后续数据层边界。
7. 提交本执行账号自己的 PR，审阅完整差异，核对所有必需 CI 和回归结果；测试失败不得跳过。
8. 合并自己提交的 PR，验证 main 和 Issue #35 验收；若批量执行计划获批，直接依次执行 #36，无需逐项重复审批。

## 5. 验收标准

- [ ] `apps/mobile/` 能按文档执行依赖安装、静态分析、单元和 Widget 测试。
- [ ] Android Debug 构建通过并有 GitHub Actions 日志；未验证的本机/真机结果如实标记。
- [ ] 当前 PoC 工程、测试、既有 CI 保持可用，无破坏性迁移。
- [ ] 具有可理解的最低限度 `app → application → domain/ports` 依赖方向，没有无调用方空抽象和循环依赖。
- [ ] 两个人物切换时逻辑 scope 独立；用户不会看到“新建会话”。
- [ ] 最小导航、状态更新和依赖注入有自动化测试。
- [ ] Flutter/Dart/Java/Android 环境和复现方法有文档；iOS 仅如实注明模板/构建/真机各自状态。
- [ ] CI 不把已有 PoC 的 #31 集成测试任务意外扩张到本 Issue。
- [ ] 所有未合并的其他开发者 PR 保持原状。

## 6. 不在范围及后续依赖

- 不在 #35 建立完整 SQLite 人物、事件、导出和迁移系统，交由 [#36](https://github.com/wangyz0518-bit/erciyuan_AI/issues/36)。
- 不在 #35 实现摘要生成、归档索引、PersonaIdentity 动态更新、记忆召回，交由 [#47](https://github.com/wangyz0518-bit/erciyuan_AI/issues/47)。
- 不在 #35 部署后端、接入 DeepSeek 或任何真实模型，交由 [#38/#39](https://github.com/wangyz0518-bit/erciyuan_AI/issues/38)。
- 不在 #35 实现正式首页美术、音频、Live2D、登录和云同步，依后续 Issue 单独决定。

**本计划已获用户批准，但不是工程已开工或测试通过的证据。**
