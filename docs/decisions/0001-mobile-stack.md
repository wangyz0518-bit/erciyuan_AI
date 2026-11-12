# ADR-0001 移动端技术栈选型

- 状态：已接受
- 日期：2026-11-11
- 确认日期：2026-11-12
- 决策依据：项目发起人确认首版客户端采用 Flutter + Dart
- 相关决策：[ADR-0002 三端范围确认](0002-three-platform-scope.md)（已接受）
- 关联任务：[#8 确定移动端首选框架](https://github.com/wangyz0518-bit/erciyuan_AI/issues/8)
- 后续验证：[#10 Flutter 双端 PoC 与工程初始化](https://github.com/wangyz0518-bit/erciyuan_AI/issues/10)

## 背景

项目处于规划阶段，尚无产品代码。第一阶段需要完成手机文字聊天骨架、角色与对话记录恢复，以及形象、声音能力验证。本决策为后续建立移动端工程确定客户端框架。

约束与偏好：

- 手机优先，Android/iOS 都要覆盖。
- 交互密集：聊天流、录音、播放、角色切换、表情状态。
- 小团队、四条工作线并行，希望减少双端重复开发。
- 关注包体积、流畅度和长期维护稳定性。
- 平台范围已由 ADR-0002 确认：首版覆盖 Android、iOS，原生鸿蒙后续适配，具体时间另行确定。

## 选项

1. **Flutter**：Dart + 自绘引擎，一套 UI 覆盖 Android/iOS/桌面。
2. **React Native + Expo**：TypeScript/React，调用原生控件，生态最大。
3. **KMP + Compose Multiplatform**：共享逻辑与 UI，体积和性能接近原生。
4. **原生双端**：Android Kotlin + Compose，iOS Swift + SwiftUI。

## 评估摘要

详细数据见 [`docs/research/mobile-stack-research-20261111.md`](../research/mobile-stack-research-20261111.md)。相对比较：

| 维度 | Flutter | RN + Expo | KMP + CMP | 原生双端 |
| --- | ---: | ---: | ---: | ---: |
| 双端开发效率 | 5 | 4 | 3 | 2 |
| UI 一致性 | 5 | 3 | 4 | 1 |
| 动画/渲染可控性 | 4 | 3 | 4 | 5 |
| 包体积 | 2 | 3 | 4 | 5 |
| 生态 | 4 | 5 | 2 | 5 |
| 鸿蒙可行性 | 2 | 3 | 1 | 4 |
| 学习成本（分数越高越容易） | 3 | 3 | 2 | 2 |
| 长期维护稳定性 | 4 | 3 | 3 | 5 |

## 决定

首版 Android/iOS 客户端采用 **Flutter + Dart**。两端共用聊天界面、角色展示和交互逻辑，减少小团队的重复开发。Flutter 的渲染方式适合实现两端一致的表情切换和待机动效。包体积、流畅度及录音和播放插件的行为由双端真机验证。

后续原生鸿蒙适配按 ADR-0002 推进，届时单独核对 Flutter SDK 适配版本和录音、存储、渲染插件。

## 待确认

- 团队成员的技术栈熟练度。
- 形象展示方案（图片/序列帧/Live2D）在 Flutter 中的实际表现。
- 包体积预算与目标设备范围。
- 后续原生鸿蒙适配的具体时间、路径和维护成本（不作为首版定案的前置条件）。
- 是否需要桌面端。

## 后续验证与实施

- Android/iOS 真机 PoC 待执行，涵盖构建安装、聊天与输入、录音播放、本地记录恢复、形象组件和包体积。
- 工程目录、分层约定及 `AGENTS.md` 的实际开发命令随工程初始化补齐。
- 以上工作由 [#10 Flutter 双端 PoC 与工程初始化](https://github.com/wangyz0518-bit/erciyuan_AI/issues/10) 跟踪。记录双端结果和关键问题，再推进第一阶段功能开发。

## 状态沿革

- 初始建议按 Android/iOS 优先的前提评估 Flutter。
- 三端首版提议出现后，本记录曾标记为“前提变化，待重新评估”。
- 2026-11-11：ADR-0002 接受 Android/iOS 首版、原生鸿蒙后续适配的范围；本记录调整为提议，保留候选建议，等待 PoC 与团队确认。

- 2026-11-12：确认 Flutter + Dart，ADR 状态改为已接受。双端 PoC 与工程初始化转入 #10。

## 参考

- [移动端技术方案调研](../research/mobile-stack-research-20261111.md)
- [三端需求复核](../research/mobile-stack-review-20261111.md)
- [团队开发安排](../process/team-development.md)
- [ADR-0002 三端范围确认](0002-three-platform-scope.md)
- [CONTRIBUTING.md](../../CONTRIBUTING.md)
