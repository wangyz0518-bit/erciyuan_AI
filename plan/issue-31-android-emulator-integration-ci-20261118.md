# Issue #31：Android 模拟器集成 CI 实施与验证记录

> 技术状态：实现已提交，CI 运行结果以关联 PR 和 Actions 为准
> 日期：2026-11-18
> 任务：[Issue #31](https://github.com/wangyz0518-bit/erciyuan_AI/issues/31)
> 历史来源：[PR #32](https://github.com/wangyz0518-bit/erciyuan_AI/pull/32)、[PR #49](https://github.com/wangyz0518-bit/erciyuan_AI/pull/49)

## 目标和范围

在 `apps/mobile_poc/` 现有 Flutter 快速检查全部通过后，使用 Android API 36 / Google APIs / x86_64 / Pixel 6 模拟器实际执行两组集成测试：`integration_test/acceptance_test.dart` 和 `integration_test/storage_failure_test.dart`。保留快速检查原步骤和 PR、main push、workflow_dispatch 触发方式。长时 soak test 不纳入每次 PR。

## 历史故障与复用

- #32 已验证模拟器可以在 Actions 启动，但旧 workflow 的多行 `script` 命令彼此不保持 Shell 的工作目录；`cd apps/mobile_poc` 没有影响下一行，最终出现 `No pubspec.yaml file found`。
- #49 提供故障分析和包装脚本方案；因建立于旧 main，未整体移植旧分支。
- 当前实现直接在最新 `main` 增加 `integration` Job，使用 `reactivecircus/android-emulator-runner@v2` 官方 `working-directory: apps/mobile_poc` 输入。
- `script` 仅运行 `bash tool/run_android_integration_ci.sh`，两组测试和退出时的 logcat 采集在同一个 Bash 进程中。
- Action 代码以 Apache-2.0 授权，参考 https://github.com/ReactiveCircus/android-emulator-runner 。

## 质量与数据边界

1. `verify` 先运行 Dart 格式检查、分析、常规测试和 Debug APK 构建；快速检查失败时不启动模拟器。
2. `integration` 在 Flutter PoC 根目录验证文件存在，使用 `set -euo pipefail`，任何测试失败都令 Job 失败，不跳过失败断言。
3. 测试退出时获取模拟器 logcat，`actions/upload-artifact@v4` 保留最多 7 天；不上传 SQLite 测试数据库、录音、App 私有文件或用户数据。
4. PR 和 main push 都要有实际两组集成测试通过证据。模拟器自动输入不替代 Android 真机中文 IME、音频试听或 iOS 验证。
5. 若模拟器或测试失败，记录日志和根因后修复；不得将格式、静态分析或集成测试改为允许失败。

## 验证证据

- 关联新 PR 的 Flutter Android validation Actions Run：以 GitHub CI 结果为准，不能把已提交的代码或模拟器启动等同于集成测试通过。
- 旧 #32 Run [44262748237](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44262748237) 仅证明快速检查和模拟器启动，未成功执行两个测试。
- 本文不涉及 Live 模型、生产部署、真机或 iOS。
