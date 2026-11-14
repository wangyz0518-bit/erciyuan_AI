# 当前角色：AI 分层到 Cubism 的最小准备样本

日期：2026-11-14。当前完成到 **四层 PNG、可重建 PSD、静态素材检查器**。尚未通过 Cubism 导入、绑定、MOC3 导出与运行验证，不能称为已完成的 Live2D 动作 Demo。

## 使用

在本目录运行（需要 Node.js 和 pnpm）：

```sh
pnpm install --frozen-lockfile
pnpm run build
node serve.cjs
```

访问 http://127.0.0.1:8766 ，可逐层隐藏、切换背景、分开展示及重置。页面没有动画或关节控制。服务器仅监听本机；Ctrl+C 停止前台进程。

构建输出：
- `build/dragon-four-layers.psd`：1287 × 1222、8 位 RGB、四个独立 RGBA 图层，供 Cubism 导入验证。
- `build/preflight.json`：输入 SHA256、透明度统计及 PSD 写入再读回结果。

`build/` 和 `node_modules/` 不进 Git；PNG、提示词、脚本及依赖锁文件可复现 PSD。构建脚本只包装 PNG 原像素，不进行自动分割或补画。PNG 无色彩配置校验，Cubism 实际导入仍需检查颜色及透明度。

## 图层约定

左／右为画面方向。每张 PNG 均保留完整画布，左上角原点为 (0, 0)，不裁切、不另行缩放。PSD 从上至下为：

| 图层 | 内容 | 当前限制 |
| --- | --- | --- |
| body | 人物、头发、衣物、四肢 | 未拆分眼口、胸腹、手臂、腿与裙摆 |
| tail | 尾巴和补出的尾根 | 单片，尚无变形或物理 |
| wing-right | 画面右翼及翼根 | 单片，尚无变形或物理 |
| wing-left | 画面左翼及翼根 | 单片，尚无变形或物理 |

素材来自会话内置 imagegen，四次部件提取加两次边缘清理；不是 Seedance/Seedream 生成。参考为 C 线既有 `dragon-character-v1.png`，见[固定版本源文件](https://github.com/wangyz0518-bit/erciyuan_AI/blob/46b8d6c/apps/mobile_poc/assets/characters/dragon-character-v1.png)。完整提示词见 [prompts.md](prompts.md)。

独立生成会有局部脸、发丝与翼根差异；当前不是原图无损拆层。主体及左翼首版存在大片背景雾边，第二轮已改善；尚未验证运动边界、遮挡穿插和变形后接缝。素材用于项目验证，不能由技术测试推定商业权利已核清。

## 实测与下一步

2026-11-14：
- 四张 PNG 尺寸一致，均包含透明像素和有效内容。
- PSD 生成 5,362,214 字节；重新读入后四层名称与全部 RGBA 像素逐字节相同。
- 浏览器可显示叠层角色；白底、深灰底以及隐藏主体检查通过。静态初筛未见首版的大面积雾背景。
- Cubism 5.3.00 官方安装包已下载并由 winget 验证散列；安装返回 0x800704c7（操作取消），安装重试等待用户确认。
- Cubism 导入、真实绑定、模型导出、动作播放均未完成。

下一位制作同事可以：
1. 安装 Windows Cubism Editor，导入生成的 PSD，确认四个图层、尺寸、透明度及层序。
2. 为翼／尾创建网格和小幅变形参数，检查根部遮挡；不要用整体图片摇摆冒充身体动作。
3. 制作一个循环待机，保存 CMO3／CAN3，导出 MOC3、model3.json、纹理和 motion3.json。
4. 在 Cubism Viewer 或 App 播放真实导出模型，记录加载及动作结果；再进入胸腹呼吸、挥手和腿部换重心阶段。

完整要求见[分层任务书](../../../docs/research/dragon-layer-materials-20261114.md)和[待执行决策](../../../docs/decisions/0003-avatar-live2d-video-demo.md)。本样本不修改 App 包 Schema。
