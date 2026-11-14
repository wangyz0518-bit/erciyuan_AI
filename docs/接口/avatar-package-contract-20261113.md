# 人物资源包契约 v0.1

> 状态：用户已确认作为 v0.1 离线联调依据；Android 导入器已实现，见本轮验收记录
> 日期：2026-11-13；实现更新：2026-11-14
> 负责人：待定
> 关联：C 形象制作与驱动、A 页面装配、#10
> 本文不改变现有 Character、GenerationTask 或服务器 HTTP 接口字段

## 1. 目标与当前边界

制作方可使用任意大模型、绘图或建模流程，但最终交付必须是符合本契约的可运行资源。首轮不要求建设上传页面、生成服务器或账号服务，直接交付本地 ZIP 即可测试制作结果。

本版只接收 Live2D Cubism 人物包，不把静态 PNG、姿态拼图、视频或任意自定义骨骼 JSON 当作 Live2D 模型。MOC3 是二进制运行模型，必须由支持该格式的制作流程正确产出；把图片改后缀、生成空文件或仅写 JSON 均不合格。PSD、CMO3、CAN3 可作为制作方源文件保留，不是 App 的运行入口。

Android 独立体验器已按本契约增加外部 ZIP 导入、严格校验、受控目录加载和语义动作映射，并用官方 Mark 参考包联调。运行方法见 [体验器指南](../guides/avatar-package-preview-20261114.md)，分层证据及未验证项见 [本轮验收](../reports/avatar-package-acceptance-20261114.md)。原 AssetManager 样例入口保留；本轮不证明同事生成包或 iOS 已可用。

## 2. 交付物

交付一个 ZIP；解压根目录直接包含 manifest.json，不套额外顶层目录。一个包只包含一个人物模型和一个服装外观版本。

```text
dragon-demo-1.0.0.zip
├── manifest.json
├── preview.png
└── model/
    ├── character.model3.json
    ├── character.moc3
    ├── textures/
    │   └── texture_00.png
    ├── motions/
    │   ├── idle.motion3.json
    │   ├── wave.motion3.json
    │   └── weight_shift.motion3.json
    ├── character.physics3.json       # 可选，仅在需要时交付并引用
    ├── character.pose3.json          # 可选，模型有外形切换时交付并引用
    └── expressions/                  # 可选
        └── happy.exp3.json
```

除 manifest.json 的位置外，其他文件名和目录可变，必须通过引用定位。包内不携带 SDK、动态库、可执行程序、脚本、密钥、人物声音或聊天记录。

- [manifest JSON Schema](schemas/avatar-package-0.1.schema.json)
- [manifest 示例](examples/avatar-package-0.1/manifest.json)
- [model3.json 示例](examples/avatar-package-0.1/model/character.model3.json)
- [示例目录说明](examples/avatar-package-0.1/README.md)
- [可转发给制作方的任务书](avatar-package-producer-brief-20261113.md)

**仓库内示例只有描述文件，没有 MOC3、纹理或动作曲线，不能直接加载；不提供假二进制占位文件。**

## 3. manifest 字段

JSON 使用 UTF-8，不能包含注释、重复键、NaN 或 Infinity。字段名区分大小写。

| 字段 | 必需 | 约定 |
| --- | --- | --- |
| format | 是 | 固定 erciyuan-avatar |
| formatVersion | 是 | 固定字符串 0.1；这是包契约版本 |
| id | 是 | 人物资源标识，3–64 个小写字母、数字、下划线或连字符，字母开头；不是用户账号或数据库 Character ID |
| version | 是 | 资源版本，三段数字，如 1.0.0；同 id 的文件内容变化时必须换版本 |
| name | 是 | 展示名称，1–64 个字符 |
| renderer | 是 | 固定 live2d-cubism |
| runtimeProfile | 是 | 固定 native-r5-basic-v1，见第 4 节 |
| entry | 是 | 相对包根的 .model3.json 路径 |
| preview | 是 | 相对包根的 PNG 封面路径；不能代替模型加载 |
| actions | 是 | 语义动作字典，至少包含 idle、wave、weight_shift，至多 24 项 |
| expressions | 否 | 表情字典，省略等同空对象，至多 16 项 |

v0.1 不接受未定义的 manifest 字段；需要扩展时另行评审，避免不同制作方自行增加相互冲突的含义。支持额外动作 ID，使用小写字母、数字和下划线，字母开头。

### 动作映射

每个动作包含 label、group、index、playback；非 idle 动作另含 returnTo。index 是从 0 开始的数组索引，必须解析到入口 model3.json 的 FileReferences.Motions[group][index]。

- idle：group 固定 Idle，index 固定 0，playback 固定 loop，不写 returnTo。
- 其他动作：group 不得为 Idle，playback 固定 once，returnTo 固定 idle。
- label 只用于显示，不作为程序判断键。
- 同一动作 ID 在不同人物包中具有相同含义，但内部参数和曲线可不同。
- 首轮只允许一个 Idle 条目。wave 与 weight_shift 必须引用不同的实际动作文件，不得复制同一动作冒充两项能力。
- 可选 expressions 中每项含 label 与 name；name 对应 FileReferences.Expressions[].Name，必须唯一匹配。

以示例为例，用户触发 wave，App 查到 Actions 数组第 0 项，再交给 SDK 播放。App 不根据文件名猜动作，不根据中文显示名称分支。

### 路径规则

manifest 中路径以包根为基准；model3.json 的文件引用以 model3.json 所在目录为基准。例如入口 model/character.model3.json 中的 textures/texture_00.png 实际是包内 model/textures/texture_00.png。

路径只用 ASCII 字母、数字、下划线、连字符、点和正斜线；每段以字母、数字、下划线或连字符开头。禁止绝对路径、反斜线、冒号、空段、连续两个点、URL、软链接、重复文件名和仅大小写不同的文件。规范化后的目标必须仍位于该包根目录内。所有引用必须在包内真实存在，不能运行时从网络补取。

## 4. 运行兼容范围

native-r5-basic-v1 是本项目首次离线联调的受限兼容配置：

- 验证运行时固定为当前工程的 Cubism SDK for Native 5-r.5，Android arm64-v8a / x86_64。
- 制作方优先按 Cubism SDK 5.0 兼容目标导出。更高版本专有功能、新渲染效果或新控制器不纳入本版承诺，需单独验证后扩展配置。
- model3.json 的 Version 为整数 3；它与 Cubism SDK 版本、MOC3 二进制版本、包版本不是同一概念。
- 实际 MOC3 必须通过该 SDK 的版本兼容与一致性检查，不能只相信 manifest 的声明。
- 纹理为真实 PNG，使用普通透明 Alpha，模型背景透明；不把背景与模型烘焙成一个不透明矩形。
- 物理、Pose 和表情文件按需提供，引用了就必须齐全；不需要的能力省略对应引用。
- UserData、DisplayInfo 可保留，引用的文件也须随包提供。不得依赖自定义代码、网络资源、motion-sync、参数控制器或运动事件回调。
- 本轮不接音频：不声明 LipSync 参数组，不在动作条目中添加 Sound；语音能力另行约定。
- iOS 尚无实现，Android 通过不等于 iOS 通过。

当前渲染器在有动作更新时不会调用自动眨眼，也没有为自定义模型添加通用呼吸驱动。因此本版的呼吸和眨眼必须制作在 idle 动作中；仅写 EyeBlink 分组或 ParamBreath 名称不算实现。示例 EyeBlink 参数名只是常见命名，必须替换为模型实际存在的 ID。

## 5. 最小能力与播放语义

| 动作 ID | 制作要求 | 建议长度 |
| --- | --- | --- |
| idle | 有可见但小幅的呼吸、自然眨眼；循环起止连续，默认全身站姿稳定 | 4–8 秒循环 |
| wave | 实际完成一次打招呼，手臂与躯干协调，完成后回到待机基准 | 2–4 秒 |
| weight_shift | 至少一条腿的膝、脚或支撑状态明显变化，同时髋部与躯干配合；不能只有上半身摆动 | 3–5 秒 |

建议长度用于设计，不要求逐帧一致。技术限制：每个动作时长为有限正数，最长 20 秒；建议以 30 FPS 导出曲线，最终以 SDK 可加载和画面表现验收。

- motion3.json 的 Meta.Loop 必须与 playback 对应：idle 为 true，其余为 false。
- 动作、表情、物理、Pose 与 EyeBlink 分组中使用的模型参数或部件 ID 必须与 MOC3 一致；不能虚构参数名。
- 触发动作改变过的参数和部件可见性，应在末尾恢复到约定待机基准，避免下一动作不覆盖这些值时残留姿态。
- 各动作条目显式提供 FadeInTime / FadeOutTime，建议各 0.3 秒；最终检查衔接，不只检查数值。
- idle 的首尾需在视觉上连续；一次动作的完成与回位不能靠人物瞬间跳变。
- v0.1 App 同时只播放一个完整触发动作。播放期间其他动作按钮禁用或返回 busy，不叠加、不累积队列；完成后回到 idle。重置允许取消动作并回到默认待机。
- 暂停应冻结当前画面，恢复继续；切换人物应清理旧人物的动画与资源。这些由本轮 Android 包播放器实现。
- 未声明动作不可触发；不能静默用另一动作替代并报告成功。

本轮关注固定视角人物互动，不验收自由三维相机、完整行走系统、精确口型或多人交互。

## 6. 首轮资源上限

以下是本项目拟定的联调上限，不是 Live2D 官方统一限制；后续依据真机测量调整。

| 项目 | v0.1 上限 |
| --- | --- |
| ZIP 文件大小 | 64 MiB |
| 解压总大小 | 128 MiB |
| 包内普通文件数 | 256 |
| 单个 JSON | 1 MiB |
| 单个二进制资源 | 64 MiB |
| 纹理数量 | 1–4 张 |
| 每张纹理尺寸 | 每边最多 2048 像素 |
| 预览图尺寸 | 每边最多 1024 像素 |
| 模型数量 | 1 |

ZIP 只接受常规 Stored / Deflate，不接受加密包、符号链接或分卷包。导入器需在解压前检查声明大小，并在解压期间按实际写入字节再次限额；读取纹理须在分配解码缓冲前检查尺寸。本轮导入器已实施这些限额；SDK 解码前再次检查纹理尺寸。

## 7. 接收、验证与验收

检查结果必须分层记录，不能把 JSON 校验通过写成模型已能运行。

| 层次 | 检查内容 | 通过意味着什么 |
| --- | --- | --- |
| 结构检查 | ZIP、路径、大小、JSON Schema、引用、动作映射、版本声明 | 包结构符合草案 |
| SDK 检查 | MOC3 兼容与一致性、真实纹理解码、动作与可选资源加载 | 当前 SDK 能读入该包 |
| 画面检查 | 人物可见，待机呼吸眨眼，wave 与 weight_shift 效果正确，衣物/肢体/翅尾遮挡无明显破损 | 声明能力在画面中成立 |
| App 检查 | 外部包导入，动作按钮、回待机、暂停恢复、重置、切换及重开可用 | 第二步到第三步完整链路通过 |

最低联调场景：

1. 外部选择 ZIP，检查通过后原子安装到 App 私有目录，显示包版本和动作列表。
2. 无网络时加载并连续待机 30 秒，观察循环接缝。
3. wave、weight_shift 各触发 3 次；每次完成后回待机，连续触发不得产生叠加穿模。
4. 动作播放期间暂停/恢复、重置；切换人物及重新打开应用后可重新加载本地包。
5. 分别提供缺失纹理、错误动作索引、不兼容模型、非法路径的失败用例；明确报错，失败包不替换当前可用包。
6. 保存包标识/版本、ZIP SHA-256、运行时与设备、各阶段结果和必要截图/录像。记录不应包含真实聊天内容。

结构错误和语义错误要能区分，例如 manifest 无效、资源缺失、运行时不支持、模型无效、动作映射无效、渲染失败；正式错误码在导入器实现时评审。

本轮不会仅用帧计数、动作命令返回成功或静态封面来证明人物显示正确。模拟器测试不替代真机性能、耗电或长时间稳定性测试。

### 描述文件检查

本草案的 manifest 示例已通过 Schema 校验；缺失腿部动作、目录越界、绝对路径、错误渲染类型、错误循环、错误返回动作、未知字段和错误 Idle 索引这 8 类变异输入均被拒绝。三个示例动作也能正确解析到示例 model3.json 的条目。该结果仅覆盖描述文件，不覆盖示例中尚不存在的模型、纹理和动作曲线。

Windows PowerShell 7 可从仓库根目录检查示例：

```powershell
Test-Json -LiteralPath docs/接口/examples/avatar-package-0.1/manifest.json -SchemaFile docs/接口/schemas/avatar-package-0.1.schema.json
```

## 8. 双方接下来分别做什么

制作方：
- 先产出一个真实可运行的包，角色可使用有权用于测试的现成模型；无须先复刻龙角角色外观。
- 确保三个标准动作的语义确实成立；若现成模型不支持腿部动作，应明确说明，不冒充完整验收包。
- 如果工具只能输出图片或视频，交付能力说明供另议格式；不伪造 .moc3 或把设计图标记为最终模型。

App 方已实现（Android）：
- 增加外部 ZIP 的选择、校验、解压与本地版本管理。
- 将模型读取从仅 AssetManager 扩展到受控本地目录，包含 model3、纹理、动作及所有附属引用。
- 解析 manifest 并映射动作，补齐播放状态、回待机、暂停、重置与取景适配。
- 使用已知可运行的参考包先验证导入器，再测同事生成的包，区分制作问题与播放器问题。

手动把模型打包进 APK 仍可用于单独检查 SDK 与视觉兼容性，但不得把这种方式记为外部 ZIP 导入通过。

## 9. 参考与证据

- [Live2D 官方嵌入数据与导出说明](https://docs.live2d.com/en/cubism-editor-manual/export-moc3-motion3-files/)：运行包、导出兼容目标和动作数据。
- [Live2D 官方 Native 模型加载说明](https://docs.live2d.com/en/cubism-sdk-manual/model/)：model3.json 引用及模型/纹理加载。
- 当前加载实现：[Java 插件](../../packages/live2d_avatar/android/src/main/java/dev/erciyuan/live2d/Live2dPlugin.java)、[原生渲染器](../../packages/live2d_avatar/android/src/main/cpp/avatar.cpp)。
- [既有验证记录](../reports/live2d-flutter-poc-20261112.md)。本契约未改变其已验证与未验证范围。
