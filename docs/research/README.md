# 调研索引

| 文档 | 主题 | 日期 | 状态 | 主要结论 |
| --- | --- | --- | --- | --- |
| [avatar-live2d-video-review-20261113.md](avatar-live2d-video-review-20261113.md) | 人物模型与视频动作可行性复核 | 2026-11-13 | 草案 | 两条路线可试验，关键制作与衔接能力待测 |
| [avatar-dual-demo-plan-20261113.md](avatar-dual-demo-plan-20261113.md) | 双 Demo 实施与验收 | 2026-11-13 | 待执行 | 同任务验证，缺失资源明确记录 |
| [mobile-stack-research-20261111.md](mobile-stack-research-20261111.md) | 移动端框架技术调研 | 2026-11-11 | 供参考 | Android/iOS 前提下建议 Flutter 优先 |
| [mobile-stack-review-20261111.md](mobile-stack-review-20261111.md) | 三端需求复核 | 2026-11-11 | 待评审 | 含原生鸿蒙时建议 uni-app 优先，Flutter 备选 |

## 结论差异

两份报告的结论不同，原因是需求前提不同：

- 第一份把鸿蒙视为未来可能项，主要比较 Android/iOS。
- 第二份把 Android、iOS、原生鸿蒙都作为首版目标，并据此重新评估。

两份报告都保留，不覆盖、不改写。最终采用哪个方向，由团队确认后写入 [`decisions/`](../decisions/README.md)，调研报告本身不作为定案依据。

## 当前决策

[ADR-0002](../decisions/0002-three-platform-scope.md) 已确认：首版覆盖 Android、iOS，原生鸿蒙后续适配，具体时间另行确定。上表保留两份报告各自的历史前提和建议，当前平台范围以该 ADR 为准。

[ADR-0001](../decisions/0001-mobile-stack.md) 已接受，首版客户端采用 Flutter + Dart。双端真机验证见 [#10 Flutter 双端 PoC 与工程初始化](https://github.com/wangyz0518-bit/erciyuan_AI/issues/10)。

## 待补

- 首版 Android/iOS 构建、录音播放、本地存储、形象渲染的 PoC 结果。
- 后续原生鸿蒙适配启动时，另补对应平台的验证结果。
- 团队对 Flutter 开发和双端构建的熟悉程度。
