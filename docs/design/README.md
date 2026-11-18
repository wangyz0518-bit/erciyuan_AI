# 设计与原型

本目录保存产品原则、界面参考板和可点击原型。原型用于验证信息架构与交互，不自动构成技术实现或正式产品决策。

| 文档 | 用途 | 状态 |
|---|---|---|
| [person-centered-companion-principles-20261118.md](person-centered-companion-principles-20261118.md) | 人物中心、每人物一条持续对话、三层记忆、用户数据所有权与导出原则 | 已确认产品原则；技术方案待评审 |
| [person-centered-home-reference-board-20261118.md](person-centered-home-reference-board-20261118.md) | 竞品公开资料、PR #15/#16/#33 复用情况及 A/B 方案比较 | 讨论稿 |
| [person-centered-home-prototype-20261118.html](person-centered-home-prototype-20261118.html) | 人物主页优先 A / 最近对话优先 B 的可点击原型，含人物切换与数据导出示例 | 可交互原型 |
| [flutter-memory-first-architecture-20261118.md](flutter-memory-first-architecture-20261118.md) | 正式 Flutter 架构、PoC 迁移、模块边界、记忆优先执行 | #34 设计基线；技术选择待 #35 确认 |
| [person-memory-data-contract-20261118.md](person-memory-data-contract-20261118.md) | 三层记忆数据、归档/检索/身份更新、导出与测试契约 | #34 设计草案，不是已实现数据库 |
| [examples/person-memory-export-fixture-v0.json](examples/person-memory-export-fixture-v0.json) | 两个人物、全合成、可验证来源引用的导出格式示例 | 设计用测试数据 |

## 打开原型

可直接在浏览器打开 HTML 文件，无需安装依赖或启动服务。也可使用[浏览器预览](https://htmlpreview.github.io/?https://github.com/wangyz0518-bit/erciyuan_AI/blob/main/docs/design/person-centered-home-prototype-20261118.html)查看交互原型；若第三方预览服务不可用，可下载 HTML 后本地打开。

原型中的人物、消息、记忆摘要和导出内容均为合成演示数据。浏览器本地存储仅用于演示持久化，不代表正式数据存储或三层记忆已实现。
