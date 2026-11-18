# Issue #36：正式人物时间线、SQLite 事实层及导出

> 状态：代码/SQLite CI 验证已通过；等待自审/合并。
> 基线：#35 PR #52 / main 4ce827a4ee53fb554a10a1e1cd664d55c76af252
> 复用评审：apps/mobile_poc/lib/data.dart 和 chat_controller.dart 的角色过滤、事务、重启恢复、取消与存储故障负向测试；PR #16/#21/#22 仅只读参考，不整分支合并。

## 范围
- 与 #34 数据契约一致：复合 owner+character 的 Character、唯一 CharacterTimeline、RawEvent、GenerationTask；各实体 ID 稳定、sequence 在每个人物内单调。
- SQLite schema v2：v1 事实存储；v2 增加生成任务表（迁移可测试），所有 append 在事务里同时写事件和前进游标，失败回滚。
- JSON 导出当前 owner **全部人物**，包含完整原始历史、人物资料、稳定 timeline_id、生成状态、可追溯事件 ID，未来记忆/身份/附件字段以空数组预留。
- 主工程本次增加事实 Repository，不提前更换 #35 Mock 主页；#37 正式 UI 接入真实数据、#47 增加记忆层。

## 验收证据（CI 后更新）
- [x] SQLite 创建、v1→v2 迁移、关闭重开恢复
- [x] 多人物多 owner 隔离、分页和导出完整性/不串数据
- [x] 幂等请求、重复事件事务失败回滚、取消失败数据不进入上下文
- [x] Flutter analyze/test 与 Android Debug 构建 CI — [Run 44293997877](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44293997877)
- [x] 现有 PoC 文件未改变（PR #53 的变更路径核验）

注意：内存 fixture 所用 owner 不是服务器鉴权。导出内容包含用户聊天，正式分享/UI/删除与授权在后续任务实现。本 Issue 的 SQL 迁移不自动改造 PoC 本机 schema v1。**导出 API** 已可一次取回全部原始数据；实际可点击的 App 数据管理导出入口由 #37 实装，不将当前 API 等同已验证的用户文件分享流程。
