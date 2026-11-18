# Issue #39：真实 Provider 接口的离线端到端测试（2026-11-19）

本轮对已实现的 FastAPI / DeepSeek SSE adapter / SQLite request ledger 增加独立的“live 配置下零网络”契约测试。以 httpx.MockTransport 截获提供商 HTTP，测试请求头、缓存前缀与记忆上下文、SSE 增量及完成、推理内容不泄露、幂等重放、owner 权限隔离与上游 401 安全错误。

测试运行位置：services/person_gateway/tests/test_gateway_live_contract.py。真实请求密钥为明确无效的 test-key；不会消耗付费模型或传出私人数据。

该测试只说明接口和存储链路在离线模拟下成立。真实模型响应、Prompt Cache、质量、计费、延迟、Android/iOS 真机、真实账号鉴权和公网部署均未验证。#39 缺少经授权的真实密钥和预算前必须保持开放，不可把测试模拟视为实际服务调用。
