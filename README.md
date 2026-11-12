# 二次元 AI 陪伴软件 · erciyuan_AI

面向手机使用的 AI 陪伴产品，计划支持角色形象、声音和性格定制，以及文字、语音交流和简单表情表现。

## 当前状态

本仓库处于规划与团队协作准备阶段。目前包含开发计划、配图和文档生成工具，尚无产品代码或可运行的应用。计划中的功能、测试数量和验收条件均为目标，不代表已经实现。

第一阶段先完成手机文字聊天骨架、可恢复的角色和对话记录，并分别验证形象、声音能力。完整语音联动、普通用户角色创建、完整记忆和用量管理在后续阶段推进。

首版平台范围已确认：**Android、iOS；原生鸿蒙后续适配，具体时间另行确定**。决策依据见 [ADR-0002](docs/decisions/0002-three-platform-scope.md)，客户端采用 **Flutter + Dart**，见 [ADR-0001](docs/decisions/0001-mobile-stack.md)。双端 PoC 和工程初始化见 [#10 Flutter 双端 PoC 与工程初始化](https://github.com/wangyz0518-bit/erciyuan_AI/issues/10)。

## 从这里开始

1. 阅读 [开发计划索引](planning/README.md)：以第一阶段详版 v2.0 为实施计划入口。
2. 阅读 [团队开发安排](docs/process/team-development.md)：确认四条工作线、共同接口和首批任务。
3. 阅读 [协作规则](CONTRIBUTING.md)：通过任务分支和 Pull Request 合作。

| 工作线 | 范围 | 负责人 |
| --- | --- | --- |
| A | 手机界面与交互 | 待团队分配 |
| B | 角色与对话核心 | 待团队分配 |
| C | 形象制作与驱动 | 待团队分配 |
| D | 声音处理 | 待团队分配 |

服务端技术方案、服务供应商、部署方式和成员分工尚待确定。工作线划分不等于需要部署四套独立服务。

## 获取项目

获得私有仓库访问权限后：

```sh
git clone https://github.com/wangyz0518-bit/erciyuan_AI.git
cd erciyuan_AI
```

当前不需要启动应用。若要重新生成 Word 计划，参考 [文档工具说明](planning/README.md#重新生成文档)。

## 目录

- `AGENTS.md`：AI 协作规则与项目约束。
- `docs/`：文档索引入口，详见 `docs/README.md`。
- `docs/state.md`：当前阶段、待办、风险。
- `docs/process/`：团队安排、协作流程与文档规范。
- `docs/research/`：移动端选型调研与复核。
- `docs/decisions/`：技术选型与架构决策记录。
- `docs/guides/`：配置与操作指南。
- `docs/接口/`：接口契约草案，暂缓整理，后续迁到 `docs/api/`。
- `.github/`：Issue 与 Pull Request 模板。
- `planning/output/`：四份正式 Word 计划，保留原文件及版本。
- `planning/assets/`：规划配图；其中聊天界面图为概念示意，不是运行截图。
- `planning/build_*.py`：文档生成脚本。
- `planning/inspect_pdf.py`：PDF 排版检查工具。

本地排版检查产物、环境配置和密钥不纳入 Git。Flutter 工程目录随工程初始化建立。
