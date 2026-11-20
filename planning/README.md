# 历史计划文档与生成工具

本目录保留早期形成的 Word 计划、配图和生成脚本，作为历史资料及原始背景参考。

**当前产品规划入口是 [产品计划](../plan/product-plan.md)。** 本目录中的旧计划不再作为当前实施计划、成员分工或任务状态的依据。旧文档与当前产品方向存在差异时，以已接受 ADR 和当前产品计划为准；尚未确认的差异通过 Issue 讨论。

## 历史文档

| 文档 | 历史用途 |
| --- | --- |
| [完整开发计划：第一阶段详版 v2.0](output/二次元AI陪伴软件_完整开发计划_第一阶段详版_v2.0.docx) | 早期第一阶段工作线、交付和验收安排 |
| [整体框架：两页版 v1.0](output/二次元AI陪伴软件_整体框架_两页版_v1.0.docx) | 早期产品目标与体验范围概览 |
| [四条工作线开发计划 v1.0](output/二次元AI陪伴软件_四条工作线开发计划_v1.0.docx) | 早期工作线拆分 |
| [第一版项目企划书 v1.0](output/二次元AI陪伴软件_第一版项目企划书_v1.0.docx) | 早期产品、路线与预算设想 |

原始文件保留，不因当前计划更新而覆盖。文档中的工作线和旧任务安排仅作历史背景。

## 重新生成历史文档

仅阅读历史文档无需安装工具。重新生成时需要 Python 3.10 或更高版本，建议使用虚拟环境：

    python -m venv .venv
    # Windows PowerShell 使用 .venv/Scripts/python.exe；其他平台使用 .venv/bin/python
    .venv/Scripts/python.exe -m pip install -r planning/requirements.txt
    .venv/Scripts/python.exe planning/build_detailed_workstreams.py

以上命令从仓库根目录运行。生成脚本会覆盖对应的 output/ 文件，运行前确保修改已保存；需要保留原版本时先在临时副本中生成和检查。

| 脚本 | 产物 |
| --- | --- |
| build_plan.py | 第一版项目企划书，以及本地成本计算快照 cost_check.json |
| build_framework.py | 整体框架两页版，并重新绘制 assets/product_framework.png |
| build_workstreams.py | 四条工作线开发计划 v1.0 |
| build_detailed_workstreams.py | 第一阶段详版 v2.0 |

build_framework.py 和 build_workstreams.py 复用 build_plan.py 的初始化部分。生成脚本和排版环境按早期 Windows 环境准备，其他系统需自行配置中文字体。

## 排版检查

先用 Word 或其他可用文档转换工具将企划书导出为 planning/qa/plan.pdf，再运行：

    .venv/Scripts/python.exe planning/inspect_pdf.py

检查脚本只处理该路径的 PDF，输出每页截图、提取文本和拼图；不会自动把 Word 转成 PDF，也不会检查所有历史计划。

qa*/ 和 cost_check.json 为本地生成产物，已排除上传。正式 Word 文件与配图纳入版本管理。聊天配图仅为概念示意。
