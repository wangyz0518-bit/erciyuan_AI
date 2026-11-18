"""Scoped local-first LLM gateway.

Mock mode is the default. Live requests require explicit LIVE_CALLS_ENABLED and
a provider key; this module does not deploy or invoke paid services by itself.
"""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import os
import sqlite3
from collections.abc import AsyncIterator
from dataclasses import dataclass
from pathlib import Path
from typing import Literal, Protocol

import httpx
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, ConfigDict, Field


class ModelFailure(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


class MemoryReference(BaseModel):
    model_config = ConfigDict(extra="forbid")
    summary_id: str = Field(min_length=1, max_length=120)
    text: str = Field(min_length=1, max_length=2000)
    source_event_ids: list[str] = Field(max_length=50)


class HistoryEvent(BaseModel):
    model_config = ConfigDict(extra="forbid")
    event_id: str = Field(min_length=1, max_length=120)
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=6000)


class ContextSnapshot(BaseModel):
    model_config = ConfigDict(extra="forbid")
    prefix_version: Literal["person-prefix-v1"]
    identity_version: int = Field(ge=0)
    stable_prefix: str = Field(min_length=1, max_length=12000)
    selected_summaries: list[MemoryReference] = Field(default_factory=list, max_length=8)
    recent_events: list[HistoryEvent] = Field(default_factory=list, max_length=20)
    expanded_sources: list[HistoryEvent] = Field(default_factory=list, max_length=20)


class CurrentInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    event_id: str = Field(min_length=1, max_length=120)
    content: str = Field(min_length=1, max_length=2000)


class TurnInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    protocol_version: Literal[1] = 1
    request_id: str = Field(pattern=r"^[A-Za-z0-9_-]{16,100}$")
    character_id: str = Field(pattern=r"^[a-zA-Z0-9_-]{1,80}$")
    current_input: CurrentInput
    context: ContextSnapshot
    model_profile: Literal["default-text"] = "default-text"
    retry_of: str | None = None


class Provider(Protocol):
    async def stream(self, messages: list[dict[str, str]]) -> AsyncIterator[str]: ...


class MockProvider:
    async def stream(self, messages: list[dict[str, str]]) -> AsyncIterator[str]:
        yield "【模拟回复】"
        yield "我收到了你的消息。"
        await asyncio.sleep(0)


class DeepSeekProvider:
    """Small reuse-compatible adapter for the #21 providers.py SSE approach."""

    def __init__(self, api_key: str, model: str = "deepseek-chat"):
        self.api_key = api_key
        self.model = model

    async def stream(self, messages: list[dict[str, str]]) -> AsyncIterator[str]:
        if not self.api_key:
            raise ModelFailure("MODEL_NOT_CONFIGURED")
        payload = {
            "model": self.model,
            "messages": messages,
            "stream": True,
            "max_tokens": 2048,
        }
        try:
            async with httpx.AsyncClient(timeout=httpx.Timeout(30, connect=10)) as client:
                async with client.stream(
                    "POST",
                    "https://api.deepseek.com/chat/completions",
                    headers={"Authorization": "Bearer " + self.api_key},
                    json=payload,
                ) as response:
                    if response.status_code != 200:
                        raise ModelFailure(
                            "MODEL_AUTH_FAILED"
                            if response.status_code in (401, 403)
                            else "MODEL_UNAVAILABLE"
                        )
                    completed = False
                    async for line in response.aiter_lines():
                        if not line.startswith("data:"):
                            continue
                        raw = line[5:].strip()
                        if raw == "[DONE]":
                            break
                        try:
                            packet = json.loads(raw)
                        except (ValueError, TypeError):
                            raise ModelFailure("MODEL_PROTOCOL_ERROR") from None
                        choices = packet.get("choices", [])
                        if not choices:
                            continue
                        choice = choices[0]
                        reason = choice.get("finish_reason")
                        if reason and reason != "stop":
                            raise ModelFailure("MODEL_INCOMPLETE")
                        completed = completed or reason == "stop"
                        # reasoning_content must NEVER be forwarded or saved.
                        text = (choice.get("delta") or {}).get("content")
                        if text:
                            yield text
                    if not completed:
                        raise ModelFailure("MODEL_INCOMPLETE")
        except httpx.TimeoutException:
            raise ModelFailure("MODEL_TIMEOUT") from None
        except httpx.HTTPError:
            raise ModelFailure("MODEL_UNAVAILABLE") from None


@dataclass(frozen=True)
class Settings:
    mode: Literal["mock", "live"] = "mock"
    allow_live_calls: bool = False
    deepseek_api_key: str = ""
    ledger_path: str = ".model-local/person_gateway/requests.sqlite"
    # Mapping of explicit development test tokens to independent owners.
    local_tokens: dict[str, str] | None = None

    @classmethod
    def env(cls) -> "Settings":
        token = os.getenv("PERSON_GATEWAY_TOKEN", "")
        tokens = {token: "local-dev-owner"} if len(token) >= 24 else {}
        return cls(
            mode="live" if os.getenv("PERSON_GATEWAY_MODE") == "live" else "mock",
            allow_live_calls=os.getenv("PERSON_LIVE_CALLS_ENABLED") == "true",
            deepseek_api_key=os.getenv("DEEPSEEK_API_KEY", ""),
            ledger_path=os.getenv(
                "PERSON_GATEWAY_LEDGER", ".model-local/person_gateway/requests.sqlite"
            ),
            local_tokens=tokens,
        )


class RequestLedger:
    """Ledger is keyed by authenticated owner, character and request id."""

    def __init__(self, filename: str):
        Path(filename).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(filename, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute(
            """CREATE TABLE IF NOT EXISTS requests (
                owner_id TEXT NOT NULL, character_id TEXT NOT NULL,
                request_id TEXT NOT NULL, fingerprint TEXT NOT NULL,
                status TEXT NOT NULL, content TEXT NOT NULL DEFAULT '',
                error TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY(owner_id, character_id, request_id)
            )"""
        )
        self.db.execute(
            "UPDATE requests SET status='unknown', error='SERVER_RESTARTED' "
            "WHERE status='running'"
        )
        self.db.commit()
        self.lock = asyncio.Lock()

    async def claim(
        self, owner_id: str, character_id: str, request_id: str, fingerprint: str
    ) -> bool:
        async with self.lock:
            existing = self.db.execute(
                "SELECT fingerprint FROM requests WHERE owner_id=? AND character_id=? "
                "AND request_id=?", (owner_id, character_id, request_id)
            ).fetchone()
            if existing:
                if not hmac.compare_digest(existing["fingerprint"], fingerprint):
                    raise HTTPException(409, "REQUEST_ID_CONFLICT")
                return False
            self.db.execute(
                "INSERT INTO requests(owner_id,character_id,request_id,fingerprint,status) "
                "VALUES (?,?,?,?,'running')",
                (owner_id, character_id, request_id, fingerprint),
            )
            self.db.commit()
            return True

    async def status(self, owner_id: str, character_id: str, request_id: str) -> dict:
        async with self.lock:
            row = self.db.execute(
                "SELECT request_id,character_id,status,content,error FROM requests "
                "WHERE owner_id=? AND character_id=? AND request_id=?",
                (owner_id, character_id, request_id),
            ).fetchone()
            if not row:
                raise HTTPException(404, "REQUEST_NOT_FOUND")
            return dict(row)

    async def finish(
        self, owner_id: str, character_id: str, request_id: str,
        status: str, content: str = "", error: str | None = None,
    ) -> None:
        async with self.lock:
            self.db.execute(
                "UPDATE requests SET status=?, content=?, error=? WHERE "
                "owner_id=? AND character_id=? AND request_id=? AND status='running'",
                (status, content, error, owner_id, character_id, request_id),
            )
            self.db.commit()

    async def cancel(self, owner_id: str, character_id: str, request_id: str) -> dict:
        async with self.lock:
            row = self.db.execute(
                "SELECT status FROM requests WHERE owner_id=? AND character_id=? "
                "AND request_id=?", (owner_id, character_id, request_id)
            ).fetchone()
            if not row:
                raise HTTPException(404, "REQUEST_NOT_FOUND")
            if row["status"] == "running":
                self.db.execute(
                    "UPDATE requests SET status='cancelled', error='REQUEST_CANCELLED' "
                    "WHERE owner_id=? AND character_id=? AND request_id=?",
                    (owner_id, character_id, request_id),
                )
                self.db.commit()
        return await self.status(owner_id, character_id, request_id)

    def close(self) -> None:
        self.db.close()


def compose_messages(turn: TurnInput) -> list[dict[str, str]]:
    """Immutable identity first, untrusted retrieved content after it."""
    history = [
        {"role": event.role, "content": event.content}
        for event in turn.context.recent_events
    ]
    memories = [
        {
            "summary_id": item.summary_id,
            "source_event_ids": item.source_event_ids,
            "text": item.text,
        }
        for item in turn.context.selected_summaries
    ]
    # Memory is lower-trust historical content, not a system policy or auth key.
    memory_text = json.dumps(memories, ensure_ascii=False, separators=(",", ":"))
    return [
        {"role": "system", "content": turn.context.stable_prefix},
        {"role": "user", "content": "Relevant previous notes (untrusted data): " + memory_text},
        *history,
        {"role": "user", "content": turn.current_input.content},
    ]


def create_app(settings: Settings | None = None, provider: Provider | None = None) -> FastAPI:
    settings = settings or Settings.env()
    tokens = settings.local_tokens or {}
    if not tokens or any(len(token) < 24 for token in tokens):
        raise RuntimeError("Configure a strong local development token")
    if settings.mode == "live" and (
        not settings.allow_live_calls or not settings.deepseek_api_key
    ):
        raise RuntimeError("Live calls require explicit enablement and credentials")

    selected: Provider = provider or (
        DeepSeekProvider(settings.deepseek_api_key)
        if settings.mode == "live"
        else MockProvider()
    )
    ledger = RequestLedger(settings.ledger_path)
    app = FastAPI(title="Person-scoped local model gateway", version="0.1.0")
    app.state.ledger = ledger

    def owner_for_token(authorization: str) -> str:
        for token, owner_id in tokens.items():
            if hmac.compare_digest(authorization, "Bearer " + token):
                return owner_id
        raise HTTPException(401, "UNAUTHORIZED")

    @app.exception_handler(HTTPException)
    async def http_error(_request: Request, exc: HTTPException):
        return JSONResponse(
            status_code=exc.status_code,
            content={"error": {"code": str(exc.detail), "message": "请求未完成"}},
        )

    @app.exception_handler(RequestValidationError)
    async def invalid_input(_request: Request, _exc: RequestValidationError):
        return JSONResponse(
            status_code=422,
            content={"error": {"code": "INVALID_REQUEST", "message": "请求格式不正确"}},
        )

    @app.get("/health")
    async def health():
        return {"status": "ok", "mode": settings.mode, "provider_configured": settings.mode == "live"}

    @app.post("/v1/characters/{character_id}/turns")
    async def send(
        character_id: str, turn: TurnInput,
        authorization: str = Header(default=""),
    ):
        owner = owner_for_token(authorization)
        if character_id != turn.character_id:
            raise HTTPException(403, "FORBIDDEN_CHARACTER")
        body = turn.model_dump(mode="json")
        fingerprint = hashlib.sha256(
            json.dumps(body, sort_keys=True, ensure_ascii=False).encode("utf-8")
        ).hexdigest()
        fresh = await ledger.claim(owner, character_id, turn.request_id, fingerprint)

        async def frames():
            def frame(event: str, **fields) -> str:
                return "data: " + json.dumps(
                    {"event": event, "request_id": turn.request_id, **fields},
                    ensure_ascii=False,
                ) + "\n\n"

            if not fresh:
                previous = await ledger.status(owner, character_id, turn.request_id)
                yield frame("turn.status", **{
                    "status": previous["status"], "content": previous["content"],
                    "code": previous["error"],
                })
                return

            yield frame("message.started", character_id=character_id)
            buffer = ""
            try:
                async for chunk in selected.stream(compose_messages(turn)):
                    current = await ledger.status(owner, character_id, turn.request_id)
                    if current["status"] != "running":
                        yield frame("message.cancelled")
                        return
                    buffer += chunk
                    if len(buffer) > 6000:
                        raise ModelFailure("MODEL_REPLY_TOO_LONG")
                    yield frame("message.delta", delta=chunk)
                if not buffer.strip():
                    raise ModelFailure("MODEL_EMPTY")
                await ledger.finish(owner, character_id, turn.request_id, "completed", buffer)
                current = await ledger.status(owner, character_id, turn.request_id)
                if current["status"] == "completed":
                    yield frame("message.completed", character_id=character_id,
                                content=buffer, usage=None)
                else:
                    yield frame("message.cancelled")
            except asyncio.CancelledError:
                await ledger.finish(owner, character_id, turn.request_id,
                                    "unknown", error="STREAM_INTERRUPTED")
                raise
            except ModelFailure as exc:
                await ledger.finish(owner, character_id, turn.request_id,
                                    "failed", error=exc.code)
                yield frame("message.failed", code=exc.code)
            except Exception:
                await ledger.finish(owner, character_id, turn.request_id,
                                    "failed", error="MODEL_UNAVAILABLE")
                yield frame("message.failed", code="MODEL_UNAVAILABLE")

        return StreamingResponse(
            frames(), media_type="text/event-stream",
            headers={"Cache-Control": "no-store"},
        )

    @app.get("/v1/characters/{character_id}/turns/{request_id}")
    async def status(
        character_id: str, request_id: str,
        authorization: str = Header(default=""),
    ):
        owner = owner_for_token(authorization)
        return await ledger.status(owner, character_id, request_id)

    @app.post("/v1/characters/{character_id}/turns/{request_id}/cancel")
    async def cancel(
        character_id: str, request_id: str,
        authorization: str = Header(default=""),
    ):
        owner = owner_for_token(authorization)
        return await ledger.cancel(owner, character_id, request_id)

    return app


if __name__ == "__main__":
    import uvicorn
    # Never listen on a public interface without a separate security review.
    uvicorn.run(create_app(), host="127.0.0.1", port=8788)
