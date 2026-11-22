# 项目交付记录

本记录以 2026 年 11 月 22 日归档前的正式版本 `4b9089f` 为基线。表中列出 wangyz0518-bit 发起的 PR 及其关联工作。评估个人参与时，可从各 PR 的 Commits、Files changed、评审和验收记录查看具体作者与改动。共同开发的项目基础和其他参与者的工作可从[全部已合并 PR](https://github.com/wangyz0518-bit/erciyuan_AI/pulls?q=is%3Apr+is%3Amerged)追溯。

| 阶段 | 交付与可核验结果 | 原始记录 |
| --- | --- | --- |
| 平台与开发环境 | 复核移动端选型，记录 Android/iOS 范围和 Flutter + Dart 决策，整理 Windows Android 环境与模拟器验证 | [调研 #2](https://github.com/wangyz0518-bit/erciyuan_AI/pull/2)、[平台 #9](https://github.com/wangyz0518-bit/erciyuan_AI/pull/9)、[技术栈 #11](https://github.com/wangyz0518-bit/erciyuan_AI/pull/11)、[环境 #12](https://github.com/wangyz0518-bit/erciyuan_AI/pull/12) |
| 聊天原型 | 制作沉浸聊天设计，完成 Flutter 页面、本地录音和试听联调。Android PoC 的早期过程也保存在单独 PR | [早期 PoC #13](https://github.com/wangyz0518-bit/erciyuan_AI/pull/13)、[原型 #15](https://github.com/wangyz0518-bit/erciyuan_AI/pull/15)、[实现 #16](https://github.com/wangyz0518-bit/erciyuan_AI/pull/16)、[验收记录](immersive-chat-flutter-20261112.md) |
| 角色形象实验 | 验证绘制分层、真实 Live2D 模型与待机动作。独立 Android 实验进一步覆盖导入、动作播放、坏包拒绝和重启恢复 | [制作验证 #20](https://github.com/wangyz0518-bit/erciyuan_AI/pull/20)、[实验原始提交与报告](../archive/live2d-poc-20261114/README.md) |
| 声音方案与桌面验证 | 从四种表达的验证提案开始，进行三模型听感比较，接入模型网关、流式朗读，试验音色微调，完成录音复刻、试听与角色绑定 | [提案 #18](https://github.com/wangyz0518-bit/erciyuan_AI/pull/18)、[桌面对比 #19](https://github.com/wangyz0518-bit/erciyuan_AI/pull/19)、[网关 #21](https://github.com/wangyz0518-bit/erciyuan_AI/pull/21)、[流式朗读 #22](https://github.com/wangyz0518-bit/erciyuan_AI/pull/22)、[微调 #23](https://github.com/wangyz0518-bit/erciyuan_AI/pull/23)、[复刻 #24](https://github.com/wangyz0518-bit/erciyuan_AI/pull/24) |
| 正式 App 与浏览器体验 | 把按角色朗读、按住说话、连续通话和插话接入正式对话界面，增加角色动态呈现和浏览器体验，修复本机预览网络配置 | [按角色朗读 #84](https://github.com/wangyz0518-bit/erciyuan_AI/pull/84)、[按住说话 #85](https://github.com/wangyz0518-bit/erciyuan_AI/pull/85)、[连续通话 #86](https://github.com/wangyz0518-bit/erciyuan_AI/pull/86)、[形象 #87](https://github.com/wangyz0518-bit/erciyuan_AI/pull/87)、[浏览器 #88](https://github.com/wangyz0518-bit/erciyuan_AI/pull/88)、[预览修复 #89](https://github.com/wangyz0518-bit/erciyuan_AI/pull/89) |
| v3 语音集成 | 以 Windows 已测试的会话为基准接入正式移动端，保留角色时间线、三种输入、插话与每轮延迟，补充 iOS 移植和安装入口 | [移植说明 #69](https://github.com/wangyz0518-bit/erciyuan_AI/pull/69)、[正式集成 #90](https://github.com/wangyz0518-bit/erciyuan_AI/pull/90)、[Windows 验证](windows-conversation-20261118.md) |
| Android 龙角角色 | 从面部变化扩展到肩胸起伏、双臂和画面右侧摊掌，分别预览五种状态及连续动作。正式 v4 聊天页通过 Android 模拟器验证，真机性能待测 | [制作素材、脚本与各版演示](../../planning/demos/dragon-motion/README.md)、[正式集成 #91](https://github.com/wangyz0518-bit/erciyuan_AI/pull/91) |

合并前的历史统计为 63 个已合并 PR，其中 22 个由该账号发起。Git 主线有 131 笔非合并提交，其中 38 笔以该账号为主作者。龙角角色的[两笔开发提交](https://github.com/wangyz0518-bit/erciyuan_AI/pull/91/commits)在正式版本合为一笔。功能规模、制作轮次与测试范围可在上表逐项查阅。
