# Issue #31：Android 模拟器集成测试 CI 执行计划

> 状态：待项目发起人确认；确认前不修改产品/CI 代码，不更新或合并 PR #32
> 日期：2026-11-18
> 当前 main：`bdda1714f5a467b7f3028f981777f2405316a0bc`
> 关联：[Issue #31](https://github.com/wangyz0518-bit/erciyuan_AI/issues/31)、[早期 PR #32](https://github.com/wangyz0518-bit/erciyuan_AI/pull/32)

## 1. 目标

在现有 Flutter Android 快速检查之后，增加独立的 Android API 36 模拟器集成测试 Job，自动执行当前 main 已有的两组测试：

- `apps/mobile_poc/integration_test/acceptance_test.dart`
- `apps/mobile_poc/integration_test/storage_failure_test.dart`

保持快速检查 Job 不变；长时间 `soak_test.dart` 继续手动运行，不纳入每次 PR 的必需路径。

## 2. 当前状态与失败根因

### 2.1 当前 main

- 当前 main：`bdda1714f5a467b7f3028f981777f2405316a0bc`。
- `.github/workflows/flutter-android.yml` 当前只有快速 Job：Java 17、Flutter 3.50.0、依赖安装、格式检查、静态分析、unit/widget 测试和 Android Debug APK 构建。
- `apps/mobile_poc/pubspec.yaml` 位于 Flutter 工程根目录，当前 Flutter SDK 约束为 Dart 3.14。
- 两个目标集成测试文件均已存在于 main；不需要重新编写测试。
- `integration_test/soak_test.dart` 是 15 分钟长时间测试，不应进入每次 PR 的必需 Job。

### 2.2 早期 PR #32 的实测

[PR #32](https://github.com/wangyz0518-bit/erciyuan_AI/pull/32) 已提交 Android API 36 / x86_64 模拟器 Job、测试命令和 logcat artifact。

GitHub Actions Run [#44262748237](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44262748237) 显示：

| Job / 步骤 | 结果 |
|---|---|
| Analyze, test, and build Android | 通过 |
| Android Emulator 启动 | 通过，启动约 46 秒 |
| Run Android integration tests | 失败 |
| Upload emulator logcat | 通过 |

失败发生在测试启动前，错误为：

`Error: No pubspec.yaml file found.`

根因：PR #32 在 `script` 中把 `set -euo pipefail`、`trap`、`cd apps/mobile_poc` 和两条测试命令分成多行。当前 Android Emulator Runner 对脚本行分别执行，`cd` 和 `trap` 不会保留到后续命令。因此测试命令实际在仓库根目录运行，两个测试文件并未真正执行。

另外，早期 logcat artifact 的 trap 在测试命令之前就因独立 Shell 退出而触发，捕获时间点不正确。

### 2.3 旧 PR 分支状态

- PR #32 由当前执行账号 keeyangyy 提交，属于本执行者自己的 PR。
- 分支 `ci/android-integration-tests` 仅领先 3 个提交，但比当前 main 落后 34 个提交，且与 main 已分叉。
- 不建议在旧分支上强推或直接合并；采用当前 main 建立干净的后继分支，选择性移植有效改动。
- 新 PR 合并后，将旧 PR #32 标记为被后继 PR 替代并关闭；保留旧提交历史供追溯。

## 3. 已有成果复用

| 来源 | 复用内容 | 处理方式 |
|---|---|---|
| PR #32 | API 36、google_apis、x86_64、Pixel 6 profile、KVM、禁用动画、45 分钟超时 | 选择性移植到最新 main |
| PR #32 | `acceptance_test.dart` 与 `storage_failure_test.dart` 执行命令 | 保留测试本身，只修正执行工作目录和 Shell 生命周期 |
| PR #32 | logcat artifact、7 天保留 | 保留目的，修复捕获时机 |
| main | 现有快速 Job 和 Flutter 3.50.0 工具链 | 原样保留，不重复实现 |
| main | 两个集成测试文件和测试夹具 | 直接复用，不重写测试逻辑 |

不合并其他成员的 PR；本次仅处理本执行者自己的旧 PR #32，并以新 PR 作为后继。

## 4. 拟执行方案

### 4.1 分支策略

用户确认后：

1. 从最新 main 创建 `ci/android-integration-tests-v2`。
2. 只移植本计划涉及的 workflow、测试执行包装脚本和文档变更。
3. 不从落后 34 个提交的旧分支继续开发，不强推覆盖旧分支。
4. 新建后继 PR，关联 Issue #31。

### 4.2 Workflow 设计

在 `.github/workflows/flutter-android.yml` 中保留现有 `verify` Job，增加：

- `integration` Job，依赖 `verify`，只有快速检查通过后才启动模拟器。
- `runs-on: ubuntu-latest`，`timeout-minutes: 45`。
- Java 17、Flutter 3.50.0 stable。
- ReactiveCircus Android Emulator Runner v2。
- Android API 36、`google_apis`、`x86_64`、`pixel_6`。
- KVM、禁用动画、无窗口模拟器；保留当前已成功启动的配置。
- 设置 action 官方支持的 `working-directory: apps/mobile_poc`，确保测试命令在 Flutter 工程根目录执行。
- 保留 PR 和 main push 触发；继续支持 `workflow_dispatch` 手动运行。

### 4.3 稳定的测试包装脚本

新增 `apps/mobile_poc/tool/run_android_integration_ci.sh`：

- 使用一个 Bash 进程执行两组测试。
- `set -euo pipefail` 确保任一测试失败都会使 Job 失败。
- 在同一个 Shell 中注册 EXIT trap，测试无论成功或失败都会在退出前执行 `adb logcat -d`。
- logcat 输出到 `$GITHUB_WORKSPACE/android-emulator-logcat.txt`。
- Workflow 的 emulator runner 只调用一条命令：`bash tool/run_android_integration_ci.sh`，不再依赖多行 Shell 之间保留 `cd` 或 trap 状态。

测试命令：

```bash
flutter test integration_test/acceptance_test.dart -d emulator-5554 --reporter expanded
flutter test integration_test/storage_failure_test.dart -d emulator-5554 --reporter expanded
```

### 4.4 日志和数据边界

- 使用 `actions/upload-artifact@v4` 上传 `android-emulator-logcat.txt`。
- Artifact 保留 7 天，失败时也执行上传步骤。
- 不上传 SQLite 测试数据库、录音、音频文件、应用私有目录或用户个人数据。
- 两个测试应继续使用唯一命名的测试数据库；不得操作开发者真实数据。
- 不把 logcat 作为产品用户数据归档。

### 4.5 文档

更新：

- `apps/mobile_poc/README.md`：区分快速检查、模拟器集成测试和手动 soak test；说明 CI 的执行方式。
- `docs/guides/flutter-poc-guide-20261112.md`：记录模拟器版本、CI 行为、logcat artifact、排障和验证边界。

不修改正式产品架构、模型服务或原始测试的验收含义。

## 5. 执行步骤

1. 用户确认本计划。
2. 从最新 main 建立后继分支。
3. 增加 Bash 包装脚本和 emulator integration Job。
4. 更新 README 和 Flutter 指南。
5. 自审 workflow、Shell 脚本、路径、artifact 和敏感数据边界。
6. 提交自己的 PR 并关联 Issue #31。
7. 等待 GitHub Actions：快速 Job 和模拟器 Job 均通过。
8. 若测试失败，先确认命令确实从 `apps/mobile_poc` 执行，再根据真实断言/运行日志修复；不得通过跳过测试、降低断言或隐藏失败来获得绿色状态。
9. 检查失败时 logcat artifact 的时间范围和内容，确认它在测试退出时捕获。
10. 作者完成并记录自审；确认无冲突、必需 CI 通过、验收证据完整后合并自己的后继 PR。
11. 后继 PR 合并后，关闭旧 PR #32 并说明被替代。
12. 确认 main push 的 CI 再次通过，更新 Issue #31 和总执行计划，再向项目发起人汇报。

## 6. 验收条件

- [ ] PR 和 main push 都能触发 Android 模拟器集成测试。
- [ ] 快速检查 Job 保持通过。
- [ ] Android 模拟器 API 36 / x86_64 成功启动。
- [ ] 两个目标集成测试在 `apps/mobile_poc` 中真实执行并通过。
- [ ] 日志明确显示 Flutter 工程目录和两个测试文件的执行结果，不再出现找不到 `pubspec.yaml`。
- [ ] 测试成功和失败时均能捕获对应时间段的 logcat。
- [ ] logcat artifact 保留 7 天；没有上传数据库、录音或其他用户数据。
- [ ] README 与 Flutter 指南准确区分快速测试、模拟器集成测试和 soak test。
- [ ] 不把模拟器结果描述为 Android 真机、iOS 或人工音质验收。

## 7. 风险与边界

- Android Emulator Runner 启动初期出现短暂 `adb device offline`，旧 Run 在约 46 秒后成功启动；当前证据表明主要失败原因是工作目录，不是模拟器启动。
- Flutter 集成测试会重装应用并操作测试数据库，必须使用 CI 的临时模拟器和唯一测试库。
- 测试中的文本输入由 Flutter Test 驱动，不替代真实中文 IME 选词验收。
- 模拟器 AudioTrack 状态不替代真机人工试听。
- 不执行 15 分钟 soak test，不增加 iOS 或真机 Job。
- 如果修正路径后出现真实测试断言失败，必须保留失败证据并修复根因，不能将测试改成跳过或只跑一部分。

## 8. 本计划的确认边界

本文件是 Issue #31 的执行方案，不是执行完成报告。当前仅完成现状调查和失败根因定位；在项目发起人确认前：

- 不修改 workflow 或测试文件；
- 不创建后继代码分支；
- 不更新、合并或关闭旧 PR #32；
- 不关闭 Issue #31。
