# v0.1 人物包独立体验器

> 状态：Android 联调实现；真机与 iOS 待验收
> 日期：2026-11-14
> 负责人：待定
> 范围：C 线，第二步资源制作 → 第三步 App 播放；不包含生成服务器

独立 `live2d` flavor 默认进入人物包体验页。点击「导入 ZIP」，选择制作方交付的 v0.1 包。结构与 SDK 检查通过后，自动播放自然待机，并根据 manifest 显示动作按钮。播放期间其他动作禁用，完成后回待机；支持暂停、继续、重置、选择已导入版本和重启恢复。页面没有关节滑块。

可运行参考包在本机 `.local/avatar-packages/mark-demo-1.0.1.zip`。它使用官方 SDK 中的 Mark MOC/纹理/物理数据，加上本项目制作的三个动作，**不是龙角角色的正式模型，也不是大模型自动建模的成果**。Model 与 SDK 二进制不提交 Git，使用及转交遵循其原始授权；重新生成前先准备官方 SDK。

## 制作并测试参考包

从仓库根目录运行。设备默认为 `emulator-5580`，首次使用先执行原 Live2D 指南的 `prepare`。

```powershell
# 从真实 Mark 渲染器生成封面和参数范围记录。
pwsh -File apps/mobile_poc/tool/live2d.ps1 -Action package-fixture
# PowerShell 7.4+ 原生重定向保留二进制数据。
& D:/dev/android-sdk/platform-tools/adb.exe -s emulator-5580 exec-out run-as dev.erciyuan.companion_poc.live2d cat app_flutter/mark-preview.png > .local/live2d/evidence/mark-preview.png
pwsh -File apps/mobile_poc/tool/make-avatar-package.ps1

# 测试用输入位于 App 外部，不打包进 APK。
& D:/dev/android-sdk/platform-tools/adb.exe -s emulator-5580 push .local/avatar-packages /data/local/tmp/
pwsh -File apps/mobile_poc/tool/live2d.ps1 -Action package-acceptance

# 测试后恢复普通入口；不要把 instrumentation 入口留给用户。
pwsh -File apps/mobile_poc/tool/live2d.ps1 -Action build
& D:/dev/android-sdk/platform-tools/adb.exe -s emulator-5580 install -r apps/mobile_poc/build/app/outputs/flutter-apk/app-live2d-debug.apk
& D:/dev/android-sdk/platform-tools/adb.exe -s emulator-5580 push .local/avatar-packages/mark-demo-1.0.1.zip /sdcard/Download/
& D:/dev/android-sdk/platform-tools/adb.exe -s emulator-5580 shell am start -n dev.erciyuan.companion_poc.live2d/dev.erciyuan.companion_poc.MainActivity
```

打包脚本输出标准包、同一 Mark 模型的切包测试夹具，以及 18 种错误包。`-Version` 可更改资源版本；`-PreviewPath` 可指定封面。相同输入采用稳定的 JSON 字段顺序和 ZIP 时间戳，同一 id/version 不允许换内容。重新渲染的封面即使只有像素变化，也需要提升版本。

旧入口保留：`lib/main_live2d_samples.dart` 为参数研究样例；`lib/main_dragon_idle.dart` 为单图 2.5D 预览；`lib/main_avatar_demos.dart` 为 Live2D/视频对照。它们与 ZIP 体验入口分开。

## 实现与故障定位

| 位置 | 职责 |
| --- | --- |
| `apps/mobile_poc/lib/avatar_package_page.dart` | 文档选择器、限额复制、包选择、动作按钮、生命周期 |
| `packages/live2d_avatar/android/src/main/java/dev/erciyuan/live2d/AvatarPackage.java` | ZIP 中央/本地头、路径、声明/实际解压量、CRC、manifest、引用、曲线、PNG 头检查 |
| 同目录 `StrictJson.java` | 严格 UTF-8、重复键、有限数值、嵌套深度检查 |
| 同目录 `AvatarPackageStore.java` | 私有暂存、内容哈希目录、原子安装记录、版本冲突、恢复完整性 |
| 同目录 `Live2dPlugin.java` | 串行导入事务、SDK 成功后选择新包、失败保留旧人物、语义动作接口 |
| `packages/live2d_avatar/android/src/main/cpp/avatar.cpp` | 受控目录读取、MOC 检查、真实参数/部件检查、纹理解码、动作完成状态、全身适配 |

导入阶段错误码为 `package_structure` 或 `package_sdk`，运行中的第二个动作返回 `package_busy`；其他插件错误保留 `live2d_error`。错误文字会指出缺失文件、动作映射、版本冲突或 SDK 失败原因。界面「结构 / SDK 通过」不等于视觉验收通过。

Cubism Native R5 的 JSON 读取器对紧凑数字和科学记数法存在限制。插件将已严格解析的描述文件在内存中规范化，再交给 SDK；原始文件与 ZIP/content SHA-256 不变。曲线须使用 Cubism 导出顺序（Model → Parameter → PartOpacity），避免 SDK 跳过后续曲线。SDK 对 PartOpacity 使用虚拟参数，本适配器将其应用到经过验证的真实部件。

全部读取限制在 App 私有包根内。支持 Stored/Deflate；不支持 ZIP64、分卷、加密、链接、可执行文件或外部下载引用。资源上限见契约；另外对 JSON 深度（64）、ZIP 条目数（含目录 512）、模型动作数（256）、单动作曲线数（4096）进行防御性限制。

包的有效性按结构、SDK、画面、App 四层判断。检查失败不会把封面当成可运行人物显示。`preview.png` 仅为封面，页面中的人物来自原生纹理渲染。真实服务生成流程、同事模型、不同服装/复杂遮挡、表情/Pose/PartOpacity 的完整组合、iOS 和真机性能仍需分别验收。
