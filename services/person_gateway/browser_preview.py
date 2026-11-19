"""Serve the private GitHub Pages preview over loopback with the official gateway."""
import json
import os
import secrets
import time
from urllib.parse import urlsplit

from starlette.datastructures import Headers
from starlette.middleware.cors import CORSMiddleware
from starlette.responses import JSONResponse, PlainTextResponse, RedirectResponse

from character_speech import CharacterSpeech
from gateway import Settings, create_app


class BrowserPreview:
    def __init__(self, app, upstream_token, page, port):
        self.app = app
        self.upstream_token = upstream_token
        self.page = page
        url = urlsplit(page)
        self.origin = f"{url.scheme}://{url.netloc}"
        self.host = f"127.0.0.1:{port}"
        self.grants = {}
        self.sessions = {}
        self.cors = CORSMiddleware(self.route, allow_origins=[self.origin],
                                   allow_methods=["GET", "POST"], allow_headers=["Authorization", "Content-Type"],
                                   expose_headers=["X-Voice-Mode"])

    async def __call__(self, scope, receive, send):
        if scope["type"] == "lifespan":
            return await self.app(scope, receive, send)
        headers = Headers(scope=scope)
        if headers.get("host") != self.host:
            return await self.reject(scope, receive, send)
        if scope["path"] == "/start" and scope["type"] == "http":
            if scope["method"] != "GET" or headers.get("sec-fetch-dest") != "document" or headers.get("sec-fetch-mode") != "navigate":
                return await self.reject(scope, receive, send)
            self.expire()
            grant = secrets.token_urlsafe(28)
            self.grants[grant] = time.monotonic() + 90
            response = RedirectResponse(self.page + "#grant=" + grant, status_code=303,
                                        headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer", "X-Frame-Options": "DENY"})
            return await response(scope, receive, send)
        if headers.get("origin") != self.origin:
            return await self.reject(scope, receive, send)

        async def send_private(message):
            if message["type"] == "http.response.start":
                message = {**message, "headers": list(message["headers"]) + [(b"cache-control", b"no-store")]}
                if scope["method"] == "OPTIONS" and headers.get("access-control-request-private-network") == "true":
                    message["headers"].append((b"access-control-allow-private-network", b"true"))
            await send(message)

        return await self.cors(scope, receive, send_private)

    def expire(self):
        now = time.monotonic()
        for collection in (self.grants, self.sessions):
            for key in [key for key, end in collection.items() if end <= now]:
                del collection[key]

    @staticmethod
    async def reject(scope, receive, send):
        if scope["type"] == "websocket":
            return await send({"type": "websocket.close", "code": 1008})
        return await PlainTextResponse("Open the preview on the gateway computer to connect.", status_code=403)(scope, receive, send)

    async def route(self, scope, receive, send):
        self.expire()
        headers = Headers(scope=scope)
        if scope["path"] == "/preview/connect" and scope["type"] == "http" and scope["method"] == "POST":
            body = bytearray()
            while True:
                event = await receive()
                if event["type"] != "http.request":
                    return
                body.extend(event.get("body", b""))
                if len(body) > 512:
                    return await self.reject(scope, receive, send)
                if not event.get("more_body"):
                    break
            try:
                grant = json.loads(body)["grant"]
                accepted = isinstance(grant, str) and self.grants.pop(grant, None) is not None
            except (ValueError, KeyError, TypeError):
                accepted = False
            if not accepted:
                return await self.reject(scope, receive, send)
            token = secrets.token_urlsafe(32)
            self.sessions[token] = time.monotonic() + 8 * 3600
            return await JSONResponse({"token": token})(scope, receive, send)

        protocol = headers.get("sec-websocket-protocol", "")
        token = protocol.removeprefix("companion.") if scope["type"] == "websocket" else headers.get("authorization", "").removeprefix("Bearer ")
        if token not in self.sessions:
            return await self.reject(scope, receive, send)
        if scope["path"] == "/preview/ready" and scope["type"] == "http":
            return await JSONResponse({"ready": True})(scope, receive, send)
        if not scope["path"].startswith("/v1/characters/"):
            return await self.reject(scope, receive, send)
        forwarded = [(k, v) for k, v in scope["headers"] if k not in (b"authorization", b"sec-websocket-protocol")]
        forwarded.append((b"authorization", ("Bearer " + self.upstream_token).encode()))

        async def respond(event):
            if event["type"] == "websocket.accept":
                event = {**event, "subprotocol": protocol}
            await send(event)

        await self.app({**scope, "headers": forwarded}, receive, respond)


def preview_app():
    token = secrets.token_urlsafe(40)
    os.environ["PERSON_GATEWAY_TOKEN"] = token
    settings = Settings.env()
    speech = CharacterSpeech.env()
    if settings.mode != "live" or speech.mode != "live":
        raise RuntimeError("Browser preview requires live text and live character speech")
    speech.binding("local-dev-owner", "star")
    return BrowserPreview(create_app(settings, speech=speech), token,
                          os.environ.get("COMPANION_PREVIEW_PAGE", "https://wangyz0518-bit.github.io/erciyuan_AI/"), 18791)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(preview_app(), host="127.0.0.1", port=18791, access_log=False, proxy_headers=False)
