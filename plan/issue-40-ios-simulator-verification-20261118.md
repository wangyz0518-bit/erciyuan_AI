# Issue #40 — iOS Simulator 构建与运行验收

- 关联 Issue：[#40](https://github.com/wangyz0518-bit/erciyuan_AI/issues/40)
- 日期：2026-11-18
- 目标：在真实的 GitHub-hosted macOS/Xcode 环境构建、安装、启动 `apps/mobile/` iOS Simulator 应用，并执行可用的正式工程集成测试。

## 实施

1. `.github/workflows/official-mobile-ios.yml` 使用 `macos-15`（因 macOS 26 首次与重跑均未进入任务步骤即 cancelled）、Flutter 3.50.0 和本机 Xcode，运行 `flutter build ios --simulator --debug --no-codesign`。
2. `apps/mobile/tool/run_ios_simulator_ci.sh` 选取可用 iPhone Simulator、启动、安装 `Runner.app`、执行 `simctl launch` 并截取实际模拟器画面。
3. 若正式工程包含 `integration_test/acceptance_test.dart`、`storage_failure_test.dart`，对同一 Simulator 运行真实 SQLite/人物隔离集成测试；如果尚无该测试（在 #37 合并前的旧 main），明确打印未执行，不代替验收。
4. 上传模拟器截图及未经签名的 `Runner.app` 压缩产物作为证据，不上传私有凭据、不进行公网部署。

## 验收判据

- [ ] Xcode 和 Flutter macOS 运行环境识别成功
- [ ] iOS Simulator 无签名构建成功
- [ ] iPhone Simulator 安装、启动和启动页截图成功
- [ ] #37 合并后，正式集成测试在 iOS Simulator 通过
- [ ] macOS CI 可重复运行并保存构建及截图证据
- [ ] 记录真机、Apple Developer 签名及发布仍未验证

## 复用说明

正式工程 `apps/mobile/ios/` 采用 Flutter 3.50 模板及 Swift Package Manager，不重新复制 PoC 工程。历史 PR #16/#21/#22 的经验仅作为兼容性参考。无可用授权的第三方资源不会进入此任务。

本记录只说明项目技术与真实测试范围，不包含个人账号操作偏好或审批规则。

## 2026-11-19 执行器故障与重试

- Actions [#44344176615](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44344176615) attempt 1 / attempt 2 均记录为 failure；唯一 macOS job 为 cancelled，未分配运行器，无任何 build/test steps 或可下载 job log。
- 两次结果不能用作 iOS 代码错误证据，也不能据此宣称 iOS 已运行。
- 将 `runs-on` 调整为 GitHub 官方支持的 `macos-15`，触发一次独立构建/模拟器测试；是否真正通过以新作业的完整步骤为准。

## 2026-11-19 已完成的正式 iOS Simulator 验收

真实 GitHub Actions 执行记录：[Official Flutter iOS Simulator #44471228989](https://github.com/wangyz0518-bit/erciyuan_AI/actions/runs/44471228989)，针对 main 提交 `07eb9b8a3bda610f3ec02ffa3a112ec57c0b5dd2`（#68 合并后），**workflow / macOS job / 所有步骤均 success**：

- Flutter 3.50.0、macOS/Xcode 环境成功安装和检测，`flutter build ios --simulator --debug --no-codesign` 构建成功，实际产出 `build/ios/iphonesimulator/Runner.app`。
- 选取 iPhone 16 Pro iOS Simulator，执行 `simctl boot`、安装、启动应用（bundle id `dev.erciyuan.mobile`）；生成 `ios-person-home.png` 实际截图。
- `flutter test integration_test/acceptance_test.dart -d <simulator-udid>`：`All tests passed!`，覆盖人物持续时间线、隔离及数据库重开。
- `flutter test integration_test/storage_failure_test.dart -d <simulator-udid>`：`All tests passed!`，覆盖写入失败、事务回滚和重复事实/作用域隔离。
- Actions artifact `erciyuan-official-ios-simulator` ID `14504846550`（上传截图、无签名 Runner.app 压缩文件），存储有效期至 2026-11-26，归档过期不影响执行记录。
- 已检查 `apps/mobile/ios/Runner/Info.plist` 的麦克风与语音识别权限说明；Xcode 项目最低 iOS 目标为 15.0；没有新增放宽 ATS 的网络例外。构建日志提示 `flutter_tts` 插件未支持原生 Swift Package Manager，当前 Flutter 工具版本仍可编译；未来 Flutter 版本需要关注插件升级/兼容。

**边界**：本证据证明当时正式 App 的 iOS Simulator 构建、启动及两项集成测试通过；未使用真实 iPhone、Apple 签名或 App Store 发布。后续变更（特别是 PR #70 新增 Swift PCM）必须单独在其提交上构建测试，不得把本记录作为该新代码的编译/音质证明。#40 的原始 iOS Simulator 验收目标已有可核查成功记录；后续 iOS 特性回归分别由相关 Issue 跟踪。
