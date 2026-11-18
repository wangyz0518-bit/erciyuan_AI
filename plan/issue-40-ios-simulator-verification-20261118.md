# Issue #40 — iOS Simulator 构建与运行验收

- 关联 Issue：[#40](https://github.com/wangyz0518-bit/erciyuan_AI/issues/40)
- 日期：2026-11-18
- 目标：在真实的 GitHub-hosted macOS/Xcode 环境构建、安装、启动 `apps/mobile/` iOS Simulator 应用，并执行可用的正式工程集成测试。

## 实施

1. `.github/workflows/official-mobile-ios.yml` 使用 `macos-26`、Flutter 3.50.0 和本机 Xcode，运行 `flutter build ios --simulator --debug --no-codesign`。
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
