# 团队协作规则

## 任务与分支

每项工作先明确目的、工作线、负责人、依赖和验收条件，可通过 GitHub Issue 记录。负责人由团队确认，不按账号自动分配。

`main` 保存已合并的共同成果。日常工作使用独立分支，例如 `feat/a-chat-layout`、`feat/b-character-profile`、`docs/interface-v1` 或 `fix/voice-cancel`。

```sh
git switch main
git pull --ff-only
git switch -c docs/interface-v1
# 完成修改并检查差异后，明确选择需要提交的文件
git add <文件路径>
git commit -m "docs: define interface examples"
git push -u origin docs/interface-v1
```

首次提交前，请在自己的环境配置正确的 Git 作者姓名及邮箱；可使用个人 GitHub 提供的 noreply 邮箱。

## Pull Request

完成后向 `main` 发起 Pull Request，说明解决的问题、修改范围、验证结果及剩余事项。至少请一位伙伴审阅后合并；涉及接口变更，请相关工作线一起确认。

这是团队约定，当前未配置强制分支保护或自动化检查。初次仓库整理作为初始化提交进入 `main`。

提交尽量围绕一项任务，避免同时改写无关文档或生成大量排版产物。合并冲突先核对双方意图，不直接覆盖别人的修改，不强制推送公共分支。

## 文档与接口

- 当前计划入口和历史版本关系见 `planning/README.md`。
- 原 Word 文档保留原版本；多人协作方式以 `docs/process/team-development.md` 补充说明。
- 接口说明与样例先审阅，再连接各模块。改变字段含义或删除字段时同步更新调用方。
- 验收记录区分真实能力、模拟结果、未接通和失败项，不将规划目标标成完成。
- 修改 Word 文档时记录版本变化，并检查渲染后的排版；不要无意覆盖原版。

## 提交前检查

检查 `git status` 和 `git diff --cached`，确认只包含本次需要共享的文件。API 密钥、令牌、`.env`、私人录音、真实聊天记录和未经团队确认的个人资料不提交；示例配置只使用占位值。

文档工具变更运行相关脚本检查；Flutter PoC 的分析、单元测试和模拟器验收命令见 `docs/guides/flutter-poc-guide-20261112.md`。目前尚未配置 CI。
