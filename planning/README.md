# 开发计划索引与文档工具

## 文档阅读顺序

| 文档 | 用途及版本关系 |
| --- | --- |
| [完整开发计划：第一阶段详版 v2.0](output/二次元AI陪伴软件_完整开发计划_第一阶段详版_v2.0.docx) | 当前实施计划入口：四条工作线、共同约定、第一阶段交付与验收 |
| [整体框架：两页版 v1.0](output/二次元AI陪伴软件_整体框架_两页版_v1.0.docx) | 快速理解产品目标与体验范围 |
| [四条工作线开发计划 v1.0](output/二次元AI陪伴软件_四条工作线开发计划_v1.0.docx) | 早期工作线版本，任务细节优先参考第一阶段详版 v2.0 |
| [第一版项目企划书 v1.0](output/二次元AI陪伴软件_第一版项目企划书_v1.0.docx) | 早期产品、路线与预算参考；候选技术与成本不表示团队已定案 |

原 Word 文件完整保留，没有为多人开发重写原文。团队并行安排见 [团队开发安排](../docs/team-development.md)。发生范围差异时先记录并由团队确认，不混用不同版本的阶段目标。

## 重新生成文档

只阅读计划无需安装工具。重新生成时需要 Python 3.10 或更高版本，建议使用虚拟环境：

```sh
python -m venv .venv
# Windows PowerShell 使用 .\.venv\Scripts\python.exe；其他平台使用 .venv/bin/python
.venv\Scripts\python.exe -m pip install -r planning/requirements.txt
.venv\Scripts\python.exe planning/build_detailed_workstreams.py
```

以上命令从仓库根目录运行。生成脚本会覆盖对应的 `output/` 文件，运行前确保修改已保存；需要保留原版本时先在临时副本中生成和检查。

| 脚本 | 产物 |
| --- | --- |
| `build_plan.py` | 第一版项目企划书，以及本地成本计算快照 `cost_check.json` |
| `build_framework.py` | 整体框架两页版，并重新绘制 `assets/product_framework.png` |
| `build_workstreams.py` | 四条工作线开发计划 v1.0 |
| `build_detailed_workstreams.py` | 完整开发计划第一阶段详版 v2.0 |

`build_framework.py` 和 `build_workstreams.py` 复用 `build_plan.py` 的初始化部分，保持脚本同目录。`build_plan.py` 读取仓库内 `assets/mobile_chat_concept.png`，不再依赖原作者电脑上的图片路径。

文档使用微软雅黑字体；框架配图脚本明确读取 Windows 的 `C:\Windows\Fonts\msyh.ttc`。当前这套排版工具按 Windows 环境准备，其他系统需自行配置可用中文字体后再生成，不能保证排版完全相同。依赖文件提供版本范围，非完全锁定的构建环境。

## 排版检查

先用 Word 或其他可用文档转换工具将企划书导出为 `planning/qa/plan.pdf`，再运行：

```sh
.venv\Scripts\python.exe planning/inspect_pdf.py
```

检查脚本只处理该路径的 PDF，输出每页截图、提取文本和拼图；不会自动把 Word 转成 PDF，也不会检查所有四份计划。其他计划可分别导出并检查。

`qa*/` 和 `cost_check.json` 为本地生成产物，已排除上传。正式 Word 文件与两张配图纳入版本管理。聊天配图仅为概念示意。
