# v0.1 人物包链路验收

> 状态：Android 模拟器联调；用户观感与真机待验收
> 日期：2026-11-14
> 负责人：待定
> 契约：`docs/接口/avatar-package-contract-20261113.md`

## 输入与环境

- 标准包：`mark-demo`，资源版本 `1.0.1`，格式 `0.1`，581,327 字节。
- ZIP SHA-256：`c8be253643ddaeae1cb70cfad799a0cbca5eb96f8da8709e0e8e2ceba24cd668`。
- 模型来自已准备的官方 SDK Mark；三个动作由打包脚本生成真实 motion3 曲线，封面来自实际模型渲染。没有调用人物生成大模型。
- 运行时：Cubism Native 5-r.5，`native-r5-basic-v1`；Flutter Android `live2d` flavor。
- 设备：`Flutter_Live2D_API36` / `emulator-5580`，Android API36，x86_64，SwiftShader。Wi-Fi 与移动数据关闭时执行主流程。

## 分层结果

| 层次 | 结果与证据边界 |
| --- | --- |
| 结构 | 外部 ZIP 经过同一导入器验证，含 manifest、模型、纹理、物理和三个动作；不是直接加载 APK 固定路径 |
| SDK | MOC 版本与一致性、真实参数 ID、PNG 解码、motion3 加载通过；破损 MOC、错误参数和破损 PNG 被 SDK 层拒绝 |
| 动作 / 画面 | 原生截图可见完整人物、打招呼时抬臂、换重心时腿脚位置改变；待机采样包含呼吸与闭眼。截图和参数不能单独证明所有时刻的衔接质量，最终观感交给用户试用 |
| App 自动化 | 连续待机 30 秒；wave / weight_shift 各三次；完成回 idle；忙碌与暂停时拒绝触发；动作中暂停/继续与重置；失败后原包仍可播放；切包、后台恢复及销毁/重建后的私有包恢复通过 |

切包夹具与标准包使用同一个 Mark MOC，证明切换包记录及资源生命周期，**不证明两个不同制作方模型的视觉适配**。普通 APK 中另已通过系统文件选择器，从 Downloads 选择标准 ZIP 导入，显示结构/SDK 通过；点击「换重心」可见腿脚变化且动作期间按钮禁用。强制停止进程后重新启动，成功恢复 `mark-demo@1.0.1`。本轮仍未触发真实 Surface 回收，不能声称回收后动作时间线续播已验证。

## 错误包

18 类错误输入均要求拒绝，且拒绝后继续播放原包的 wave：缺纹理、越界动作索引、不兼容 MOC 版本、截断 MOC、路径穿越、JSON 重复键、虚构参数、曲线计数错误、大小写冲突、同版本内容变化、损坏纹理、过大封面、未知 manifest 字段、字符串索引、符号链接、声明大小超限、实际解压量超限、加密标志。

用例同时断言 SDK 类错误确实发生在 SDK 层；实际解压超限用例修改 ZIP 声明长度，确认不是只信头部大小。大小写冲突用例使用区分大小写的字典构建，确保 ZIP 中真的存在两条不同大小写的记录。

## 验证命令与本地证据

- `-Action package-fixture`：真实 Mark 封面与参数目录。
- `-Action package-acceptance`：Android instrumentation，最终完整轮 `OK (1 test)`，92.819 秒，含上述动作和错误包断言。
- `-Action acceptance`：既有 Haru/Mark 原生与 Flutter 能力回归，`OK (1 test)`，76.283 秒。
- `-Action analyze`：无问题；`-Action test`：3 项通过。
- 打包脚本相同输入重复执行，标准 ZIP SHA-256 一致。
- `.local/live2d/evidence/avatar-package-acceptance.json`：包、哈希、待机参数范围、六次动作、失败原因和最终原生状态。
- 同目录 `mark-preview.png`、`package-wave.png`、`package-weight_shift.png`：真实原生模型截图。
- 最后以普通入口构建、安装并打开体验版，恢复本地包；非 instrumentation 测试入口。
- 最终兼容性检查移除导入器对 API26 `java.nio.file` 的依赖，保持既有 minSdk24；在普通入口重新导入并重启恢复通过，未另外运行 API24 设备。

## 待验收

同事生成的人物包、龙角角色正式 Live2D、可选表情/Pose/PartOpacity 的组合模型、Android 真机、arm64 实机、iOS、耗电和长期稳定性均未由本轮结果证明。APK 同时编译 arm64/x86_64 不代表 arm64 真机已验证。
