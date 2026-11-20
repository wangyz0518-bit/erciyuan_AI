# Issue #41 — Android 真机核心流程验收

日期：2026-11-18；关联 [Issue #41](https://github.com/wangyz0518-bit/erciyuan_AI/issues/41)。

## 工作成果

`apps/mobile/tool/run_android_physical_acceptance.sh` 是**必须在实际 Android 手机上本地运行**的验收入口。它拒绝 `emulator-*` 和 `ro.kernel.qemu=1` 的虚拟设备，检查 USB/ADB 授权，构建并安装正式 APK，启动并截图，然后运行正式工程的两个 `integration_test` 测试文件：

- `acceptance_test.dart`：人物主页、持续时间线、消息保存、人物隔离和 SQLite 重开恢复；
- `storage_failure_test.dart`：实际平台 SQLite 写入失败、事务回滚、重复事件和 owner 隔离。

所有设备细节、截图和故障日志默认保存到**执行机器的系统临时目录**，不自动提交到 Git 或上传到公共服务；人工项目记录不得包含未经同意的私人数据。

## 运行命令

```bash
ANDROID_SERIAL=<实际设备ADB序列号> \
  bash apps/mobile/tool/run_android_physical_acceptance.sh
```

需先安装 Android SDK Platform Tools 和 Flutter 3.50，打开手机 USB 调试、接受电脑 RSA 授权。脚本输出本地报告目录及需真人检查的清单。

## 验收边界

- [ ] 有实际物理 Android 设备及可核查的机型/版本记录
- [ ] 正式 APK 实机安装和启动通过
- [ ] 正式工程的 SQLite / 人物隔离集成测试实机通过
- [ ] 中文原生输入法、返回键、字体缩放、安全区域、后台恢复由真人测试并留证
- [ ] 真机缺陷修复与可自动化回归
- [ ] 设备结果、模拟器结果分开记录

**重要：** 当前仅完成可执行的真机验收工具和流程设计，尚未接入实际设备。因此本 Issue 不能因脚本存在、APK 构建通过或 Android 模拟器成功而关闭。等待实际测试环境时不阻塞后续不依赖真机的音频/语音开发。

本文件记录面向全体贡献者的设备测试要求，不包含个人账号/审批习惯。

## 2026-11-19 ADB 授权状态预检增量

为避免使用 `ANDROID_SERIAL` 指向离线、未授权或已断开的设备时误进入耗时的构建和测试流程，真机验收脚本在查询模拟器属性之前明确执行 `adb -s "$SERIAL" get-state`；仅状态为 `device` 的连接可继续。`apps/mobile/tool/test_android_physical_preflight.sh` 用仅存在于本地临时目录的**假 ADB/Flutter 命令**验证断线、未授权、不可用序列号、标准/非标准模拟器序列号会在构建前拒绝。CI 自动执行此拒绝行为测试。

该测试完全没有连接物理手机或执行实际 APK、SQLite 和人工验收；只有在真实设备执行 `run_android_physical_acceptance.sh` 并记录结果后才有资格关闭 #41。
