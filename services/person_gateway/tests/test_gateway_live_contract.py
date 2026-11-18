"""Full live-mode SSE path tested through in-process fake transport, no paid calls."""
import asyncio
import json

import httpx

from gateway import DeepSeekProvider, Settings, create_app


TOKENS = {"a" * 32: "owner-a", "b" * 32: "owner-b"}


def turn():
    return {
        "protocol_version": 1,
        "request_id": "live-contract-000000001",
        "character_id": "star",
        "current_input": {"event_id": "input-001", "content": "今天好吗？"},
        "context": {
            "prefix_version": "person-prefix-v1",
            "identity_version": 1,
            "stable_prefix": "person-prefix-v1\ncharacter=star",
            "selected_summaries": [
                {"summary_id": "memory-1", "text": "喜欢草莓", "source_event_ids": ["old-1"]}
            ],
            "recent_events": [{"event_id": "old-1", "role": "user", "content": "请记住"}],
            "expanded_sources": [],
        },
        "model_profile": "default-text",
    }


def events(response):
    return [
        json.loads(line[6:])
        for line in response.text.splitlines()
        if line.startswith("data: ")
    ]


def configured_app(tmp_path, handler):
    return create_app(
        Settings(
            mode="live",
            allow_live_calls=True,
            deepseek_api_key="test-key-no-real-provider",
            local_tokens=TOKENS,
            character_allowlist={"owner-a": {"star"}, "owner-b": {"star"}},
            ledger_path=str(tmp_path / "live-contract.sqlite"),
        ),
        provider=DeepSeekProvider(
            "test-key-no-real-provider",
            transport=httpx.MockTransport(handler),
        ),
    )


def test_live_contract_from_fastapi_through_deepseek_adapter_to_ledger(tmp_path):
    upstream = []

    async def fake_provider(request):
        upstream.append(request)
        data = json.loads(request.content)
        assert request.url.host == "api.deepseek.com"
        assert request.headers["authorization"] == "Bearer test-key-no-real-provider"
        assert data["stream"] is True
        assert data["model"] == "deepseek-chat"
        assert data["messages"][0]["role"] == "system"
        assert all(item["role"] != "assistant" for item in data["messages"])
        assert "喜欢草莓" in data["messages"][2]["content"]
        assert "请记住" in data["messages"][3]["content"]
        assert data["messages"][-1]["content"].endswith("今天好吗？")
        payload = "\n".join(
            [
                'data: {"choices":[{"delta":{"content":"很"},"finish_reason":null}]}',
                'data: {"choices":[{"delta":{"reasoning_content":"hidden","content":"好"},"finish_reason":null}]}',
                'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}',
                "data: [DONE]",
                "",
            ]
        )
        return httpx.Response(200, content=payload.encode())

    async def run():
        app = configured_app(tmp_path, fake_provider)
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://gateway-test",
        ) as client:
            path = "/v1/characters/star/turns"
            headers = {"Authorization": "Bearer " + "a" * 32}
            first = await client.post(path, json=turn(), headers=headers)
            assert first.status_code == 200
            assert [row["event"] for row in events(first)] == [
                "message.started", "message.delta", "message.delta",
                "message.completed",
            ]
            assert events(first)[-1]["content"] == "很好"
            assert "hidden" not in first.text
            retry = await client.post(path, json=turn(), headers=headers)
            assert events(retry)[0]["event"] == "turn.status"
            assert len(upstream) == 1
            result = await client.get(
                path + "/live-contract-000000001", headers=headers
            )
            assert result.json()["status"] == "completed"
            assert result.json()["content"] == "很好"
            other = await client.get(
                path + "/live-contract-000000001",
                headers={"Authorization": "Bearer " + "b" * 32},
            )
            assert other.status_code == 404
        app.state.ledger.close()

    asyncio.run(run())


def test_live_contract_sanitizes_upstream_auth_failure(tmp_path):
    async def fake_unauthorized(_request):
        return httpx.Response(401, json={"secret": "must-not-expose"})

    async def run():
        app = configured_app(tmp_path, fake_unauthorized)
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://gateway-test",
        ) as client:
            path = "/v1/characters/star/turns"
            headers = {"Authorization": "Bearer " + "a" * 32}
            response = await client.post(path, json=turn(), headers=headers)
            assert events(response)[-1]["event"] == "message.failed"
            assert events(response)[-1]["code"] == "MODEL_AUTH_FAILED"
            assert "must-not-expose" not in response.text
            result = await client.get(
                path + "/live-contract-000000001", headers=headers
            )
            assert result.json()["status"] == "failed"
            assert result.json()["content"] == ""
        app.state.ledger.close()

    asyncio.run(run())
