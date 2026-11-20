from threading import Event

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from gateway import Settings, create_app


def test_input_only_stream_is_scoped_and_commit_gated(monkeypatch):
    monkeypatch.setenv("PERSON_ASR_MODE", "demo")
    token = "t" * 32
    app = create_app(Settings(local_tokens={token: "test"}, character_allowlist={"test": {"star"}},
                              ledger_path=":memory:"))
    path = "/v1/characters/star/voice-input"
    headers = {"Authorization": "Bearer " + token}
    finished = Event()

    async def observed(scope, receive, send):
        try:
            await app(scope, receive, send)
        finally:
            if scope["type"] == "websocket":
                finished.set()

    with TestClient(observed) as client:
        for url, auth in ((path, {}), (path.replace("star", "moon"), headers)):
            with pytest.raises(WebSocketDisconnect), client.websocket_connect(url, headers=auth):
                pass
        with client.websocket_connect(path, headers=headers) as socket:
            assert socket.receive_json() == {"type": "ready", "mode": "demo"}
            socket.send_bytes(bytes(3200))
            socket.send_text("commit")
            assert socket.receive_json()["type"] == "error"
            assert socket.receive()["type"] == "websocket.close"
        with client.websocket_connect(path, headers=headers) as socket:
            assert socket.receive_json()["type"] == "ready"
            socket.send_bytes(bytes(6400))
            socket.send_text("commit")
            assert socket.receive_json() == {"type": "final", "text": "【演示转写】你好"}
            assert socket.receive()["type"] == "websocket.close"
        with client.websocket_connect(path, headers=headers) as socket:
            assert socket.receive_json()["type"] == "ready"
            finished.clear()
            socket.send_bytes(bytes(6400))
            socket.close()
            # Wait for ASR cleanup before TestClient cancels the whole ASGI task.
            assert finished.wait(3)
        assert app.state.ledger.db.execute("SELECT COUNT(*) FROM requests").fetchone()[0] == 0
