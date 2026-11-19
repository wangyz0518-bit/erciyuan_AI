"""One bounded transcription per WebSocket. The mobile timeline owns submission."""
import asyncio
import os
from dataclasses import dataclass

from fastapi import WebSocketDisconnect

from realtime_asr import ProviderError, QwenASR


@dataclass(frozen=True)
class InputSettings:
    mode: str = "off"
    dashscope_key: str = ""
    workspace: str = ""
    asr_model: str = "qwen3-asr-flash-realtime"
    voice_proxy: str | None = None

    @classmethod
    def env(cls):
        return cls(os.getenv("PERSON_ASR_MODE", "off"), os.getenv("DASHSCOPE_API_KEY", ""),
                   os.getenv("DASHSCOPE_WORKSPACE_ID", ""),
                   os.getenv("QWEN_ASR_MODEL", "qwen3-asr-flash-realtime"),
                   os.getenv("GATEWAY_VOICE_PROXY") or None)


async def serve_input(socket, settings, recognizer=None):
    await socket.accept()
    if settings.mode not in ("live", "demo") or (settings.mode == "live" and not settings.dashscope_key):
        await socket.send_json({"type": "error", "code": "ASR_NOT_CONFIGURED"})
        await socket.close()
        return

    queue = asyncio.Queue(maxsize=96)
    committed = False

    async def receive():
        nonlocal committed
        total = 0
        while True:
            message = await socket.receive()
            if message["type"] == "websocket.disconnect":
                raise WebSocketDisconnect()
            data = message.get("bytes")
            if data is not None and not committed:
                total += len(data)
                if not data or len(data) > 6400 or len(data) % 2 or total > 960000:
                    raise ProviderError("INVALID_INPUT_AUDIO")
                await queue.put(data)
                continue
            if message.get("text") == "commit" and not committed and total >= 6400:
                committed = True
                await queue.put(None)
                continue
            raise ProviderError("INVALID_INPUT")

    async def chunks():
        while (chunk := await queue.get()) is not None:
            yield chunk

    async def partial(text):
        await socket.send_json({"type": "partial", "text": text})

    async def transcribe():
        if settings.mode == "demo":
            async for _ in chunks():
                pass
            return "【演示转写】你好"
        return await (recognizer or QwenASR(settings)).transcribe(chunks(), partial)

    await socket.send_json({"type": "ready", "mode": settings.mode})
    reader = asyncio.create_task(receive())
    worker = asyncio.create_task(transcribe())
    try:
        async with asyncio.timeout(68):
            done, _ = await asyncio.wait({reader, worker}, return_when=asyncio.FIRST_COMPLETED)
            if reader in done:
                reader.result()
            text = worker.result()
            if not committed or not text.strip() or len(text) > 2000:
                raise ProviderError("ASR_INVALID_FINAL")
            await socket.send_json({"type": "final", "text": text})
    except (ProviderError, TimeoutError) as exc:
        await socket.send_json({"type": "error", "code": getattr(exc, "code", "ASR_TIMEOUT")})
    except WebSocketDisconnect:
        return
    finally:
        reader.cancel()
        worker.cancel()
        await asyncio.gather(reader, worker, return_exceptions=True)
    await socket.close()
