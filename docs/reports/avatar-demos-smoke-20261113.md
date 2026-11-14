# 双路线 Demo 技术验收记录

> 状态：评审中；完整同角色效果尚未通过
> 日期：2026-11-13
> 负责人：待定
> 关联：[运行指南](../guides/avatar-demos-20261113.md)、[决策 PR #20](https://github.com/wangyz0518-bit/erciyuan_AI/pull/20)

## 本次真实验证

- Flutter 静态分析：No issues found。
- Android API 36 专用模拟器 instrumentation：最终轮 OK (1 test)，18.441 秒。
- 测试使用实际 Cubism 渲染器加载 Mark、播放原始动作并确认帧计数增长，随后加载 Haru。
- 实际 Android 视频解码：播放进度前进，暂停位置稳定，最新请求替换前一请求，片段结束转入动作并回待机，前后台暂停恢复通过。
- 损坏视频替换被拒绝，原播放器保持可用。
- 只先导入动作、尚未导入待机时，仍可开始播放；最新轮覆盖该边界。
- 测试资源在单独的 avatar_video_demo_test 目录中，测试槽位完成后清理。

本地结构化结果：.local/live2d/evidence/avatar-demos-smoke.json。测试代码：apps/mobile_poc/integration_test/avatar_demos_test.dart。

## 测试素材与证据边界

视频测试复用了现有 dragon-idle-preview.mp4（原 App 录屏）作为三个槽位的传输测试夹具。它不是 Seedance 输出，不包含三项真实动作，不能证明人物一致性、挥手／腿部效果、无缝衔接或 AI 生成可行性已经验收。

Live2D 使用官方样例，不是当前龙角角色。动作按原始资源 ID 显示，未验收为目标语义动作。帧计数增长只证明渲染运行，不等于美术质量通过。

未验证：系统文件选择器完整人工操作、标准 ZIP 包导入、真实 AI 视频素材、同角色美术对比、循环接缝、切换首帧画质、10 分钟持续表现、Android/iOS 真机、iOS 构建、突然终止时资源恢复。

视频动作等待当前片段结束，未满足或证明拟议的 ≤1 秒响应目标。三个文件导入只是操作样机，不是现有 Live2D 包契约或正式服务接口实现。

## 交付与后续

普通入口为 main_avatar_demos.dart，运行与构建使用 live2d.ps1 的 demo-run／demo-build。两条路线共享一个菜单，进入各自独立页面；A 可使用官方模型操作，B 初始为空并提示导入素材。

后续需要当前角色正式 Live2D 模型、待机／挥手／腿部换重心三个合格 AI 视频及生成来源；取得资源后继续动作语义、衔接和同角色验收。当前仅技术底座部分通过，最终选型保持待评审。
