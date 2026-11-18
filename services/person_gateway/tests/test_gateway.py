import asyncio
import hashlib
import json
import tempfile
from pathlib import Path

import httpx
import pytest

from gateway import (
    DeepSeekProvider,
    ModelFailure,
    Settings,
    TurnInput,
    compose_messages,
    create_app,
)


TOKEN_A = "a" * 32
TOKEN_B = "b" * 32


def request_body(character="star", request_id="test-request-0000001", content="你好"):
    return {
        "protocol_version": 1,
        "request_id": request_id,
        "character_id": character,
        "current_input": {
            "event_id": "event-current-1",
            "content": content,
        },
        "context": {
            "prefix_version": "person-prefix-v1",
            "identity_version": 0,
            "stable_prefix": "person-prefix-v1\nowner=owner-a\ncharacter=" + character,
            "selected_summaries": [
                {
                    "summary_id": "memory-1",
                    "text": "user: tea preference",
                    "source_event_ids": ["old-1"],
                }
            ],
            "recent_events": [
                {"event_id": "old-2", "role": "user", "content": "hello"}
            ],
            "expanded_sources": [],
        },
        "model_profile": "default-text",
        "retry_of": None,
    }


def parse_events(body: str) -> list[dict]:
    return [
        json.loads(line[6:])
        for line in body.splitlines()
        if line.startswith("data: ")
    ]


async def create_client(tmp_path, provider=None):
    app = create_app(
        Settings(
            mode="mock",
            local_tokens={TOKEN_A: "owner-a", TOKEN_B: "owner-b"},
            ledger_path=str(tmp_path / "requests.sqlite"),
        ),
        provider=provider,
    )
    client = httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    )
    return app, client


def test_mock_stream_and_status_are_scoped_to_authenticated_owner(tmp_path):
    async def run():
        app, client = await create_client(tmp_path)
        async with client:
            url = "/v1/characters/star/turns"
            send = await client.post(
                url, headers={"Authorization": "Bearer " + TOKEN_A},
                json=request_body(),
            )
            assert send.status_code == 200
            events = parse_events(send.text)
            assert [e["event"] for e in events] == [
                "message.started", "message.delta", "message.delta",
                "message.completed",
            ]
            assert events[-1]["content"].startswith("【模拟回复】")
            assert events[-1]["usage"] is None

            saved = await client.get(
                url + "/test-request-0000001",
                headers={"Authorization": "Bearer " + TOKEN_A},
            )
            assert saved.json()["status"] == "completed"
            other = await client.get(
                url + "/test-request-0000001",
                headers={"Authorization": "Bearer " + TOKEN_B},
            )
            assert other.status_code == 404

            # Reusing the ID under another authenticated owner is independent.
            second_owner = await client.post(
                url, headers={"Authorization": "Bearer " + TOKEN_B},
                json=request_body(),
            )
            assert second_owner.status_code == 200
            assert parse_events(second_owner.text)[-1]["event"] == "message.completed"
        app.state.ledger.close()

    asyncio.run(run())


def test_authorization_character_scope_and_payload_validation(tmp_path):
    async def run():
        app, client = await create_client(tmp_path)
        async with client:
            url = "/v1/characters/star/turns"
            no_auth = await client.post(url, json=request_body())
            assert no_auth.status_code == 401
            wrong_path = await client.post(
                "/v1/characters/moon/turns",
                json=request_body(),
                headers={"Authorization": "Bearer " + TOKEN_A},
            )
            assert wrong_path.status_code == 403
            invalid = request_body()
            invalid["context"]["stable_prefix"] = ""
            bad = await client.post(
                url, json=invalid,
                headers={"Authorization": "Bearer " + TOKEN_A},
            )
            assert bad.status_code == 422
            assert "stable_prefix" not in json.dumps(bad.json())
        app.state.ledger.close()

    asyncio.run(run())


def test_idempotent_replay_and_fingerprint_conflict(tmp_path):
    class CountingProvider:
        def __init__(self):
            self.calls = 0

        async def stream(self, messages):
            self.calls += 1
            yield "test-completed"

    async def run():
        provider = CountingProvider()
        app, client = await create_client(tmp_path, provider=provider)
        async with client:
            url = "/v1/characters/star/turns"
            h = {"Authorization": "Bearer " + TOKEN_A}
            first = await client.post(url, json=request_body(), headers=h)
            assert first.status_code == 200
            assert provider.calls == 1
            replay = await client.post(url, json=request_body(), headers=h)
            assert parse_events(replay.text)[0]["event"] == "turn.status"
            assert provider.calls == 1

            modified = request_body(content="改了原来参数")
            conflict = await client.post(url, json=modified, headers=h)
            assert conflict.status_code == 409
            assert conflict.json()["error"]["code"] == "REQUEST_ID_CONFLICT"
            assert provider.calls == 1

            another_person = await client.post(
                "/v1/characters/moon/turns",
                json=request_body(character="moon"),
                headers=h,
            )
            assert another_person.status_code == 200
            assert provider.calls == 2
        app.state.ledger.close()

    asyncio.run(run())


def test_incomplete_provider_cannot_commit_success(tmp_path):
    class BrokenProvider:
        async def stream(self, messages):
            yield "incomplete"
            raise ModelFailure("MODEL_INCOMPLETE")

    async def run():
        app, client = await create_client(tmp_path, provider=BrokenProvider())
        async with client:
            url = "/v1/characters/star/turns"
            headers = {"Authorization": "Bearer " + TOKEN_A}
            result = await client.post(url, json=request_body(), headers=headers)
            events = parse_events(result.text)
            assert events[-1]["event"] == "message.failed"
            assert "message.completed" not in [e["event"] for e in events]
            status = await client.get(
                url + "/test-request-0000001", headers=headers,
            )
            assert status.json()["status"] == "failed"
            assert status.json()["content"] == ""
        app.state.ledger.close()

    asyncio.run(run())


def test_cancel_and_status_are_idempotent_and_owner_scoped(tmp_path):
    async def run():
        app, client = await create_client(tmp_path)
        fingerprint = hashlib.sha256(b"test").hexdigest()
        assert await app.state.ledger.claim(
            "owner-a", "star", "test-request-0000001", fingerprint,
        )
        async with client:
            url = "/v1/characters/star/turns/test-request-0000001/cancel"
            h = {"Authorization": "Bearer " + TOKEN_A}
            first = await client.post(url, headers=h)
            second = await client.post(url, headers=h)
            assert first.json()["status"] == "cancelled"
            assert second.json()["status"] == "cancelled"
            outsider = await client.post(
                url, headers={"Authorization": "Bearer " + TOKEN_B},
            )
            assert outsider.status_code == 404
        app.state.ledger.close()

    asyncio.run(run())


def test_prompt_order_and_live_calls_are_opt_in(tmp_path):
    turn = TurnInput.model_validate(request_body())
    messages = compose_messages(turn)
    assert messages[0]["role"] == "system"
    assert messages[0]["content"] == turn.context.stable_prefix
    assert "untrusted data" in messages[1]["content"]
    assert messages[-1]["content"] == "你好"
    with pytest.raises(RuntimeError):
        create_app(Settings(
            mode="live",
            allow_live_calls=False,
            deepseek_api_key="test-no-real-key",
            local_tokens={TOKEN_A: "owner-a"},
            ledger_path=str(tmp_path / "blocked.sqlite"),
        ))
    with pytest.raises(RuntimeError):
        create_app(Settings(
            mode="live",
            allow_live_calls=True,
            deepseek_api_key="",
            local_tokens={TOKEN_A: "owner-a"},
            ledger_path=str(tmp_path / "no-key.sqlite"),
        ))
