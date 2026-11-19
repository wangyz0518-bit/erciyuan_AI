# Issue #39：真实 Provider 接口的离线端到端测试（2026-11-19）

本轮对已实现的 FastAPI / DeepSeek SSE adapter / SQLite request ledger 增加独立的“live 配置下零网络”契约测试。以 httpx.MockTransport 截获提供商 HTTP，测试请求头、缓存前缀与记忆上下文、SSE 增量及完成、推理内容不泄露、幂等重放、owner 权限隔离与上游 401 安全错误。

测试运行位置：services/person_gateway/tests/test_gateway_live_contract.py。真实请求密钥为明确无效的 test-key；不会消耗付费模型或传出私人数据。

该测试只说明接口和存储链路在离线模拟下成立。真实模型响应、Prompt Cache、质量、计费、延迟、Android/iOS 真机、真实账号鉴权和公网部署均未验证。#39 缺少经授权的真实密钥和预算前必须保持开放，不可把测试模拟视为实际服务调用。

## 2026-11-19 预启动取消竞态修复

`StreamingResponse` 的请求指纹与 SQLite ledger claim 在 SSE generator 迭代之前完成，因此 claim 与启动模型之间可能接收到取消。新增进入流时对 ledger 状态的复核，并在实际运行 provider 前检查取消信号；将“message.started”移到保护清理的 `try/finally` 范围内。两项纯本机假 Provider 测试分别模拟：claim 后迭代前取消、收到 started 事件后首个模型任务启动前取消，要求上游调用次数为零、ledger 标记取消且没有残留 active registry。

这能阻止已知的前置取消窗口，但不能保证停止已被远端接受的真实付费请求，也不代表已取得 API 费用/隐私授权或实际模型验收。
