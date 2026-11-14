# 描述文件示例，不是可播放人物包

> 状态：草案示例
> 日期：2026-11-13
> 关联：[人物资源包契约 v0.1](../../avatar-package-contract-20261113.md)

这里只提供 manifest.json 和 model/character.model3.json，演示字段、相对路径和动作映射。没有人物二进制、纹理、封面或动作曲线，因此不能直接作为 ZIP 导入。

制作方需实际生成/导出：
- preview.png；
- model/character.moc3；
- model/textures/texture_00.png；
- model/motions/idle.motion3.json、wave.motion3.json、weight_shift.motion3.json。

模型文件、纹理、参数 ID 与动作曲线必须配套。根据真实导出结果修改 model3.json 的引用和 Groups；例子中的 EyeBlink 参数名不保证适用于你的模型。

manifest 的 idle → Idle[0]、wave → Actions[0]、weight_shift → Actions[1] 必须与 model3.json 数组一致。不要制造空 MOC3、空 PNG 或仅有字段而无有效曲线的动作文件来让结构检查通过。

可选物理/表情/Pose 应完整导出并在 model3.json 引用。无需某功能时省略引用即可。

本例只承诺 manifest 能通过对应 Schema；资源完整性、SDK 加载与 App 播放仍需真实资源测试。
