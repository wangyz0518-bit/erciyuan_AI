# Issue #35 正式 Flutter 工程实施与验收记录

- 起点 main: bf786ff877872af579926d05d96307ff69d1378b（已合并 #51）
- 复用：从 main 的 apps/mobile_poc/ **只引用** Android/iOS 原生 Flutter 模板、原有 Flutter 3.50.0 / Java 17 兼容工具链；未复制 PoC 的业务代码、数据库、Mock 生成器或录音实现。
- 从 PR #16 参考最小人物入口/角色切换与测试场景，不改其 PR，未复制整个历史分支。
- 新建 apps/mobile/ 的 app → application → domain/port → Mock adapter，角色入口、隔离草稿及独立单元/Widget 测试。
- 新增独立 Android 快速 CI；没有改 #31/#32/#49 或 .github/workflows/flutter-android.yml。

## 完成状态（验收时更新）

- [x] GitHub Actions 的 Flutter dependencies / format / analyze / flutter test 全部通过（PR #52，[Run 44291719698](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44291719698)）
- [x] GitHub Actions Android Debug APK 构建、APK artifact 上传成功（同上 Run）
- [ ] iOS 只有工程模板，未在 macOS/Xcode 验证；#40 单独处理
- [x] PR #52 变更文件检查：apps/mobile/ 76 项，PoC 0 项，其他仅专属 workflow 与计划，未触碰其他开发者 PR
- [x] 自审和最终 CI/PR 记录齐全：最终通过 [Run 44292495873](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44292495873)；PR #52 变更文件检查、来源/权限、安全和平台限制已记录。

最终 CI：Flutter 3.50.0 / Java 17；`dart format` 11 files / 0 changed；`flutter analyze` 无警告；单元/Widget 测试通过；Android Debug APK 构建及 artifact 上传成功。未执行 Android 模拟器集成测试（#31 暂缓）。

CI 首轮失败：格式 4 处；第二轮静态分析提示 material.dart 不适用于 Flutter 3.50；已根据日志修正为 material_ui，最新成功 Run 如上。依赖锁文件来自该成功 Run 的 flutter pub get 解析结果。iOS 构建/真机尚未测试。

本记录不能替代 CI 链接、真实设备证明或实际验收结论。
