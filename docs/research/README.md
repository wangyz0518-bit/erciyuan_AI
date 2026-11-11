# 调研索引

| 文档 | 主题 | 日期 | 状态 | 主要结论 |
| --- | --- | --- | --- | --- |
| [mobile-stack-research-20261111.md](mobile-stack-research-20261111.md) | 移动端框架技术调研 | 2026-11-11 | 供参考 | Android/iOS 前提下建议 Flutter 优先 |
| [mobile-stack-review-20261111.md](mobile-stack-review-20261111.md) | 三端需求复核 | 2026-11-11 | 待评审 | 含原生鸿蒙时建议 uni-app 优先，Flutter 备选 |

## 结论差异

两份报告的结论不同，原因是需求前提不同：

- 第一份把鸿蒙视为未来可能项，主要比较 Android/iOS。
- 第二份把 Android、iOS、原生鸿蒙都作为首版目标，并据此重新评估。

两份报告都保留，不覆盖、不改写。最终采用哪个方向，由团队确认后写入 [`decisions/`](../decisions/README.md)，调研报告本身不作为定案依据。

## 待补

- 三端构建、录音播放、本地存储、形象渲染的 PoC 结果。
- 团队成员技术栈熟练度与候选框架的匹配情况。