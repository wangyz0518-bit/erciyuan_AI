# Android Live2D 人物包实验归档

本目录记录截至 2026 年 11 月 14 日的独立 Flutter PoC。原始实现保存在归档合并的父提交 `020b6df5b022fd14a46f8a1e1806fb6629c872fd`。从完整克隆可单独检出当时的实现、测试、契约和工具。[原始 PR #17](https://github.com/wangyz0518-bit/erciyuan_AI/pull/17) · [源码快照](https://github.com/wangyz0518-bit/erciyuan_AI/tree/020b6df5b022fd14a46f8a1e1806fb6629c872fd)

| 实验 | 当时记录的结果 | 报告 |
| --- | --- | --- |
| 原生渲染与 Flutter 预览 | 使用 Android 模拟器验证真实模型加载、参数控制和资源生命周期 | [渲染验证](https://github.com/wangyz0518-bit/erciyuan_AI/blob/020b6df5b022fd14a46f8a1e1806fb6629c872fd/docs/reports/live2d-flutter-poc-20261112.md) |
| 动作与视频对照 | 验证模型动作、视频解码、切换及前后台暂停恢复 | [双路线演示](https://github.com/wangyz0518-bit/erciyuan_AI/blob/020b6df5b022fd14a46f8a1e1806fb6629c872fd/docs/reports/avatar-demos-smoke-20261113.md) |
| 人物 ZIP 导入 | 用官方 Mark 样本验证待机、抬臂、换重心、切包、重启恢复和 18 类失败输入。不同制作方模型、实体手机、iOS 与长期性能待验收 | [人物包验收](https://github.com/wangyz0518-bit/erciyuan_AI/blob/020b6df5b022fd14a46f8a1e1806fb6629c872fd/docs/reports/avatar-package-acceptance-20261114.md) |

在仓库根目录执行以下命令，即可在旁边的新目录打开历史版本。运行实验前按该版本指南准备 Cubism SDK 和已授权的模型资源。[历史操作指南](https://github.com/wangyz0518-bit/erciyuan_AI/blob/020b6df5b022fd14a46f8a1e1806fb6629c872fd/docs/guides/avatar-package-preview-20261114.md)

```shell
git worktree add --detach ../erciyuan-live2d-poc-20261114 020b6df5b022fd14a46f8a1e1806fb6629c872fd
```
