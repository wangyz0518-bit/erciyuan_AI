# 当前状态

> 状态：有效
> 更新：2026-11-13
> 维护：团队共同更新，阶段变化时优先更新本文件

## 阶段

第一批本地能力验证。`apps/mobile_poc` 已建立 Flutter 工程；原聊天使用模拟回复和占位角色，C 线独立入口默认展示白发龙角角色的 2.5D 自然待机，另保留官方 Live2D 样例入口。当前均为 Android 模拟器验证，真实服务与 Android/iOS 真机尚未完成，详见 [本批记录](reports/android-poc-report-20261112.md) 和 [形象验证记录](reports/live2d-flutter-poc-20261112.md)。

## 已完成

- 第一阶段开发计划与四条工作线划分。
- 移动端框架技术调研，以及按三端需求做的复核。
- 协作规则、Issue 表单、PR 模板。
- 文档目录整理与索引。
- 首版 Android/iOS 客户端选定 **Flutter + Dart**，见 [ADR-0001](decisions/0001-mobile-stack.md)。
- 三个 PoC 页面及本地存储、模拟回复、角色展示、录音播放实现；构建和检查命令见 [运行指南](guides/flutter-poc-guide-20261112.md)。
- C 线新增独立 Live2D 预览入口，官方 Haru/Mark 已在 Android 模拟器通过 Native + Flutter Texture 显示；具体检查与限制见 [Live2D 验证记录](reports/live2d-flutter-poc-20261112.md)。
- C 线增加用户指定角色的 2.5D 自然待机体验：单图网格呼吸、轻微重心与附属物摆动，支持暂停、幅度和近景；Android 模拟器画面及交互检查通过。没有完成该角色的正式 Live2D 分层与绑定。

## 进行中

- 已执行 [#10 Flutter 双端 PoC 与工程初始化](https://github.com/wangyz0518-bit/erciyuan_AI/issues/10) 的第一批七项模拟器检查。拼音选词发送、人声录制回放及六轮重启恢复已复测。此前的冷启动异常未复现，原因仍未查明。双端真机结果待补。

## 已确认的平台范围

- 首版覆盖 Android、iOS；原生鸿蒙放到后续阶段适配，具体时间另行确定。
- 原生鸿蒙不属于首版交付、PoC 或验收条件。
- 依据：[ADR-0002](decisions/0002-three-platform-scope.md)（已接受）；关联 [#7](https://github.com/wangyz0518-bit/erciyuan_AI/issues/7)。

## 待决策

| 事项 | 现状 | 决策位置 |
| --- | --- | --- |
| 形象展示方案 | 占位绘图已验证；Live2D 完成 Android 模拟器接入，真机、iOS、正式页面装配及自制模型仍待验证 | [Live2D 验证记录](reports/live2d-flutter-poc-20261112.md) |
| 接口字段 | v1 草案未评审 | `接口/README.md` |

## 风险

- Flutter 的 Android/iOS 构建、录音播放、本地存储和形象渲染仍待真机验证。
- Live2D 持续测试返回通过后，专用模拟器进程退出，详细 JSON 遗失；退出原因及真实 Surface 回收恢复仍待查证，见 Live2D 验证记录。
- 团队成员的技术栈熟练度未知，影响框架落地速度。
- 接口草案未确认，A/B/C/D 并行开发时可能出现字段不一致。

## 下一步

1. 落实 Android/iOS 真机、iOS 构建与签名环境，明确验收用例。
2. 按 #10 验证 Android/iOS 真机上的输入、录音播放、记录恢复、形象同屏和安装。冷启动异常若再现，保存启动日志并核对应用安装列表和虚拟设备数据目录。
3. 记录双端验证结果和关键问题，确认后推进第一阶段功能开发。

## 后续原生鸿蒙适配

- 适配时间与方案另行确定，不阻塞首版双端验收。
- 鸿蒙的构建、录音播放、本地存储、形象渲染均未做真机验证；启动适配时单独验证，不能用安卓 APK 在华为设备上运行代替原生鸿蒙验收。
