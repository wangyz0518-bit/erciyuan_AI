# Issue #35 正式 Flutter 工程实施与验收记录

- 起点 main: bf786ff877872af579926d05d96307ff69d1378b（已合并 #51）
- 复用：从 main 的 apps/mobile_poc/ **只引用** Android/iOS 原生 Flutter 模板、原有 Flutter 3.50.0 / Java 17 兼容工具链；未复制 PoC 的业务代码、数据库、Mock 生成器或录音实现。
- 从 PR #16 参考最小人物入口/角色切换与测试场景，不改其 PR，未复制整个历史分支。
- 新建 apps/mobile/ 的 app → application → domain/port → Mock adapter，角色入口、隔离草稿及独立单元/Widget 测试。
- 新增独立 Android 快速 CI；没有改 #31/#32/#49 或 .github/workflows/flutter-android.yml。

## 完成状态（验收时更新）

- [ ] GitHub Actions 的 Flutter dependencies / format / analyze / flutter test 全部通过
- [ ] GitHub Actions Android Debug APK 构建通过
- [ ] iOS 只有工程模板，未在 macOS/Xcode 验证；#40 单独处理
- [ ] PoC 保持不变，未触碰其他开发者 PR
- [ ] 自审和 CI/PR 记录齐全

本记录不能替代 CI 链接、真实设备证明或实际验收结论。
