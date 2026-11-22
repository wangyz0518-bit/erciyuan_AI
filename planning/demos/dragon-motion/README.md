# 龙角角色动画制作记录

Android 正式 App 使用[五个无声短片及静态封面](../../../apps/mobile/assets/dragon_avatar/)。下表保存制作过程中交付的视觉演示。点击连续片段可查看状态衔接，各版目录还保留了单状态和五状态演示。归档 MP4 直接从原文件复制视频流，已移除声音轨与原文件元数据。

| 阶段 | 观察内容 | 演示 |
| --- | --- | --- |
| 面部初版 | 眨眼、嘴形、倾听和微笑 | [初版片段](media/dragon-preview/dragon-demo.mp4) · [循环动图](media/dragon-preview/dragon-loop.webp) |
| 身体动作 | 肩胸起伏与轻笑节奏 | [连续演示](media/dragon-body-preview/continuous.mp4) |
| 手臂初版 | 抬手、放手和对话手势 | [连续演示](media/dragon-arm-preview/continuous.mp4) |
| 手臂细化 | 手腕与手势间的过渡 | [连续演示](media/dragon-arm-polished/continuous.mp4) |
| 摊掌修订 | 画面右侧手掌朝向的中间版本 | [连续演示](media/dragon-arm-corrected/continuous.mp4) |
| 末版预览 | 对照摊掌姿态，检查待机、倾听、思考、说话和轻笑 | [手臂对照](media/dragon-arm-anatomy/arm-comparison.mp4) · [五个状态](media/dragon-arm-anatomy/five-states.mp4) · [连续衔接](media/dragon-arm-anatomy/continuous.mp4) |

[原画与分层输入](art/)保留表情图集、身体关键姿势、手臂纹理和摊掌修订稿。[制作代码](source/)按当时的工作目录保留，从面部合成到最终 Android 取景均可单独查看。早期插帧实验的中间帧库由制作流程生成。

## 验证最终合成器

Windows 下用 .NET Framework 的 C# 编译器编译 [Compose.cs](source/android-avatar-render/Compose.cs)，引用 `System.Drawing.dll` 并开启 `/unsafe`。将 [Android 合成输入](art/android-avatar-render/) 中的三个 PNG 复制到一个可写工作目录。依次传入工作目录、FFmpeg 可执行文件、[手臂图集](art/dragon-arm-polished/02-arm-textures.png)、[表情图集](art/dragon-arm-polished/03-facial-expressions.png)、单声道 16 位 PCM WAV 和 `bounds`。WAV 可用合成静音，只用于驱动本次检查。省略最后的 `bounds` 会在工作目录渲染各状态片段。

归档时重新编译了最终合成器。639 帧检查中，两侧手部的横坐标范围为 100.7 至 594.6 像素，纵坐标为 306.1 至 670.7 像素。这个检查用于发现手部越出画面。Android 模拟器的正式集成结果见 [PR #91](https://github.com/wangyz0518-bit/erciyuan_AI/pull/91)。
