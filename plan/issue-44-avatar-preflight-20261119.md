# Issue #44：正式形象元信息预检与静态降级

2026-11-19。复用历史 PR #17 的 v0.1 manifest 契约及 PR #20 的模型制作记录；不复制历史 PoC 大量冲突代码，亦不提交未获授权的 Cubism SDK/Core、第三方模型或收费素材。

交付：\`AvatarManifestPreflight.inspect\` 预检固定渲染类型/版本、相对文件路径、idle/wave/weight_shift 语义动作、表达式和未知字段；配套非法路径、动作冲突、非法版本测试。Flutter 聊天页仍显示明确注明的静态形象占位，并基于 idle/talking 状态进行微小缩放动画；这不是 Live2D。

**安全边界**：Dart 的 jsonDecode 不能拒绝重复对象键；本预检也不能读取 ZIP、检查符号链接/大小/CRC/哈希、解析 moc3、验证纹理和 motion3、证明 SDK 兼容或安装/回滚。真正导入前须审查并移植 PR #17 完整的安全导入器和 Cubism 原生验证，不能单独使用此预检宣称包安全。

仍缺少：可分发的 SDK/Core 及模型的明确许可；真实角色在 Android 的独立显示与动作、切换和后台生命周期；iOS 兼容与真机人体观感/稳定性证据。Issue #44 保持开放，静态占位不得冒充 Live2D 验收。
