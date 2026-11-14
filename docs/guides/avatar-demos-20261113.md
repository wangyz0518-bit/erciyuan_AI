# 双路线 Demo 运行说明

> 状态：草案，技术演示；完整同角色效果验收未完成
> 日期：2026-11-13
> 负责人：待定
> 关联：[待执行决策 PR #20](https://github.com/wangyz0518-bit/erciyuan_AI/pull/20)

## 运行

在 C 线分支根目录执行：

```powershell
pwsh -File apps/mobile_poc/tool/live2d.ps1 -Action prepare
pwsh -File apps/mobile_poc/tool/live2d.ps1 -Action demo-run -Device emulator-5580
```

构建 APK 用 `-Action demo-build`，输出在 `apps/mobile_poc/build/app/outputs/flutter-apk/app-live2d-debug.apk`。独立入口为 `apps/mobile_poc/lib/main_avatar_demos.dart`，沿用 live2d flavor 和应用标识；安装会更新原 Live2D 体验应用，原聊天 poc flavor 不变。

SDK 和官方模型按既有 prepare 流程本地取得，不提交 Git。本入口不修改原默认单图预览入口。原始多部位调试仍从 main_live2d_samples.dart 运行。

## A：实时模型

选择 A 后默认加载 Mark，可切换 Haru，点击原始动作 ID 播放完整预设动作，完成后由既有原生逻辑回待机；支持暂停及前后台暂停恢复。不提供部位滑块。

这是官方样例接入 Demo，不是当前龙角角色。原始动作未验收为指定的挥手／换重心，因此界面保留原始名称，不伪造语义。用户指定角色仍需要正式分层、绑定和动作。

## B：视频播放器

选择 B，依次用“导入待机／挥手／换重心”选择设备上的 MP4。暂限每段大于 0 且不超过 30 秒、64 MiB，无音轨播放；由设备解码器判断是否能播放。导入后复制到应用私有目录，重新进入可恢复。此版本是三个独立文件的操作样机，不是标准 ZIP 包导入器。

点击动作会记录请求，当前片段结束后切换；期间的新点击替换前一请求。动作结束回待机。此版本每段独立解码、在末尾切换，尚未实现中间安全点切换或保证无黑帧，因此响应可能等待整段时长，不能宣称满足 ADR 的 1 秒目标。

当前没有内置 AI 角色动作视频。空状态会明确提示；已有 App 录屏只能用于播放器管线测试，不能用于证明 AI 生成质量。供应商、账号、生成额度和实际素材需另行提供。

为了保护原素材，验证不通过的视频不会替换已加载片段；文件复制或重新初始化失败时尝试恢复备份。尚未验证断电／进程终止瞬间的恢复，不作为生产资源更新协议。

## 测试

`flutter analyze --no-pub` 检查代码。Android 管线测试需要预先推送一段测试 MP4：

```powershell
adb -s emulator-5580 push <测试视频.mp4> /data/local/tmp/avatar-playback-fixture.mp4
adb -s emulator-5580 shell chmod 644 /data/local/tmp/avatar-playback-fixture.mp4
pwsh -File apps/mobile_poc/tool/live2d.ps1 -Action demo-acceptance
```

测试使用独立的 avatar_video_demo_test 私有目录，替换并清理该目录的测试槽位；正式入口使用 avatar_video_demo。测试只验证解码及调度，不要求测试视频真的包含对应动作。测试后重新执行 demo-build／demo-run 恢复普通入口。

结果记录见 [验收记录](../reports/avatar-demos-smoke-20261113.md)。真实 AI 视频、系统文件选择器交互、同角色比较、标准包导入、Android/iOS 真机、连续运行性能仍按实际测试情况填写，不能由静态分析或编译推断通过。

## 平台与范围

Live2D 当前仅 Android 实现。新增视频组件有移动端基础；本次未构建 iOS，file_picker 13.x 的官方说明要求 iOS 14+，需在 iOS 适配时评审最低系统版本。未改正式服务端实体与 Live2D 包 Schema。
