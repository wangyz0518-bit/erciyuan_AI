# Issue #44：正式形象元信息预检与静态降级

2026-11-19。复用历史 PR #17 的 v0.1 manifest 契约及 PR #20 的模型制作记录；不复制历史 PoC 大量冲突代码，亦不提交未获授权的 Cubism SDK/Core、第三方模型或收费素材。

交付：\`AvatarManifestPreflight.inspect\` 预检固定渲染类型/版本、相对文件路径、idle/wave/weight_shift 语义动作、表达式和未知字段；配套非法路径、动作冲突、非法版本测试。Flutter 聊天页仍显示明确注明的静态形象占位，并基于 idle/talking 状态进行微小缩放动画；这不是 Live2D。

**安全边界**：Dart 的 jsonDecode 不能拒绝重复对象键；本预检也不能读取 ZIP、检查符号链接/大小/CRC/哈希、解析 moc3、验证纹理和 motion3、证明 SDK 兼容或安装/回滚。真正导入前须审查并移植 PR #17 完整的安全导入器和 Cubism 原生验证，不能单独使用此预检宣称包安全。

仍缺少：可分发的 SDK/Core 及模型的明确许可；真实角色在 Android 的独立显示与动作、切换和后台生命周期；iOS 兼容与真机人体观感/稳定性证据。Issue #44 保持开放，静态占位不得冒充 Live2D 验收。


## 2026-11-19 开发者侧 ZIP 预检增量（不安装、不执行）

- 新增 `apps/mobile/tool/avatar_zip_preflight.py`：对本机角色 ZIP 进行只读检查，不解压、安装或运行任何模型。约束路径穿越、绝对路径、大小写重复文件名、Unix 软链接及特殊文件、加密 ZIP、不受支持的压缩算法、压缩炸弹风险、单文件/总大小与文件数上限；逐项流式读取校验 CRC，拒绝 JSON 重复键与缺失的入口/预览文件。
- `python3 apps/mobile/tool/avatar_zip_preflight.py /path/to/avatar.zip` 会输出仅包含角色包 ID、版本、资源数和总解压字节数的简短摘要。测试样本完全合成，不含真实角色素材。
- CI 使用 Python 标准库执行 ZIP 安全回归测试，无新增供应商 SDK 或受版权限制的模型依赖。
- **限制**：该工具不是 Flutter 端 ZIP 安装器，不检验所有 Cubism 二进制/资源引用及供应商许可，用户提供的模型不得因通过技术预检就视为获得分发授权。正式 Live2D 渲染、Flutter 导入/回滚和 Android/iOS 实机动作验收仍未完成。
