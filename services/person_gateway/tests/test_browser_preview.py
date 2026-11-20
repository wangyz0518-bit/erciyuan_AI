from fastapi import FastAPI, WebSocket
from fastapi.testclient import TestClient

from browser_preview import BrowserPreview

PAGE = "https://example.github.io/companion/"
ORIGIN = "https://example.github.io"


def client():
    app = FastAPI()

    @app.websocket("/v1/characters/star/voice-input")
    async def voice(socket: WebSocket):
        assert socket.headers["authorization"] == "Bearer server-token"
        await socket.accept()
        await socket.send_text("ready")
        await socket.close()

    return TestClient(BrowserPreview(app, "server-token", PAGE, 18791), base_url="http://127.0.0.1:18791")


def test_navigation_pairs_once_and_rejects_other_origins():
    with client() as c:
        assert c.get("/start").status_code == 403
        headers = {"Sec-Fetch-Dest": "document", "Sec-Fetch-Mode": "navigate"}
        response = c.get("/start", headers=headers, follow_redirects=False)
        prefix = PAGE + "#grant="
        assert response.headers["location"].startswith(prefix)
        grant = response.headers["location"][len(prefix):]
        assert c.post("/preview/connect", json={"grant": grant}, headers={"Origin": "https://example.net"}).status_code == 403
        token = c.post("/preview/connect", json={"grant": grant}, headers={"Origin": ORIGIN}).json()["token"]
        assert token != "server-token"
        assert c.post("/preview/connect", json={"grant": grant}, headers={"Origin": ORIGIN}).status_code == 403
        session = {"Origin": ORIGIN, "Authorization": "Bearer " + token}
        assert c.get("/preview/ready", headers=session).status_code == 200
        assert c.get("/preview/ready", headers={**session, "Origin": "https://example.net"}).status_code == 403
        assert c.get("/preview/ready", headers={**session, "Host": "example.net"}).status_code == 403
        with c.websocket_connect("ws://127.0.0.1:18791/v1/characters/star/voice-input", headers={"Origin": ORIGIN}, subprotocols=["companion." + token]) as socket:
            assert socket.accepted_subprotocol == "companion." + token
            assert socket.receive_text() == "ready"
