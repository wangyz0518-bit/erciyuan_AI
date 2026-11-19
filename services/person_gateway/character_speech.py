"""Speech for an already-committed reply. Uses the voice PoC's CosyVoice wire protocol."""
import asyncio
import base64
import hashlib
import json
import math
import os
import re
import sqlite3
import struct
import uuid
from contextlib import aclosing, closing
from dataclasses import dataclass
from pathlib import Path

from fastapi import HTTPException
from websockets.asyncio.client import connect


@dataclass(frozen=True)
class CharacterSpeech:
    mode: str = "off"
    key: str = ""
    workspace: str = ""
    catalog: str = ""
    star_voice: str = ""
    moon_voice: str = ""
    proxy: str | None = None

    model = "cosyvoice-v3.5-flash"

    @classmethod
    def env(cls):
        return cls(
            mode=os.getenv("PERSON_VOICE_MODE", "off"),
            key=os.getenv("DASHSCOPE_API_KEY", ""),
            workspace=os.getenv("DASHSCOPE_WORKSPACE_ID", ""),
            catalog=os.getenv("PERSON_VOICE_CATALOG", ""),
            star_voice=os.getenv("COSYVOICE_VOICE_ID", ""),
            moon_voice=os.getenv("COSYVOICE_YUE_VOICE_ID", ""),
            proxy=os.getenv("GATEWAY_VOICE_PROXY") or None,
        )

    def binding(self, owner, character):
        # The PoC catalogue is a single development owner's resource.
        if owner != "local-dev-owner" or character not in ("star", "moon"):
            raise HTTPException(404, "VOICE_NOT_BOUND")
        if self.mode == "demo":
            return character
        if self.mode != "live" or not self.key:
            raise HTTPException(503, "VOICE_NOT_CONFIGURED")
        if self.workspace and not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9-]{0,127}", self.workspace):
            raise HTTPException(503, "VOICE_NOT_CONFIGURED")
        if self.catalog:
            scope = hashlib.sha256(json.dumps(
                ["live", self.model, self.workspace, self.key], ensure_ascii=False
            ).encode()).hexdigest()
            try:
                with closing(sqlite3.connect(Path(self.catalog).resolve().as_uri() + "?mode=ro", uri=True)) as db:
                    row = db.execute(
                        "SELECT p.provider_id FROM bindings b JOIN profiles p ON p.id=b.profile "
                        "WHERE b.character=? AND p.status='ready' AND p.scope=?",
                        ("xing" if character == "star" else "yue", scope),
                    ).fetchone()
            except sqlite3.Error:
                raise HTTPException(503, "VOICE_CATALOG_UNAVAILABLE") from None
            voice = row[0] if row else None
        else:
            voice = self.star_voice if character == "star" else self.moon_voice
        if not voice:
            raise HTTPException(409, "VOICE_NOT_BOUND")
        return voice

    async def pcm(self, text, voice):
        if self.mode == "demo":
            frequency = 440 if voice == "star" else 660
            chunk = b"".join(struct.pack("<h", round(1400 * math.sin(
                2 * math.pi * frequency * i / 24000))) for i in range(2400))
            for _ in range(6):
                yield chunk
                await asyncio.sleep(0.05)
            return

        host = f"{self.workspace}.cn-beijing.maas.aliyuncs.com" if self.workspace else "dashscope.aliyuncs.com"
        task = uuid.uuid4().hex
        async with connect(f"wss://{host}/api-ws/v1/inference",
                           additional_headers={"Authorization": f"Bearer {self.key}"},
                           open_timeout=10, close_timeout=1, max_size=4*1024*1024, proxy=self.proxy) as socket:
            async def send(action, payload):
                await socket.send(json.dumps({
                    "header": {"action": action, "task_id": task, "streaming": "duplex"},
                    "payload": payload,
                }, ensure_ascii=False))

            await send("run-task", {
                "task_group": "audio", "task": "tts", "function": "SpeechSynthesizer",
                "model": self.model, "input": {}, "parameters": {
                    "text_type": "PlainText", "voice": voice, "format": "pcm",
                    "sample_rate": 24000, "rate": 1.0, "pitch": 1.0,
                },
            })
            ready, total, remainder = False, 0, b""
            while True:
                packet = await asyncio.wait_for(socket.recv(), 30)
                if isinstance(packet, bytes):
                    total += len(packet)
                    if not ready or total > 12 * 1024 * 1024:
                        raise ValueError("Invalid speech payload")
                    data = remainder + packet
                    end = len(data) - len(data) % 2
                    remainder = data[end:]
                    for offset in range(0, end, 9600):
                        yield data[offset:min(end, offset + 9600)]
                    continue
                header = json.loads(packet)["header"]
                if header.get("task_id") != task:
                    raise ValueError("Invalid speech task")
                event = header["event"]
                if event == "task-started" and not ready:
                    ready = True
                    await send("continue-task", {"input": {"text": text}})
                    await send("finish-task", {"input": {}})
                elif event == "task-finished" and ready and total and not remainder:
                    return
                elif event != "result-generated":
                    raise ValueError("Unexpected speech event")

    async def frames(self, text, voice):
        try:
            async with asyncio.timeout(180), aclosing(self.pcm(text, voice)) as stream:
                async for chunk in stream:
                    yield json.dumps({"pcm": base64.b64encode(chunk).decode("ascii")}) + "\n"
            yield '{"done":true}\n'
        except Exception:
            # After streaming headers are committed, signal failure in-band.
            yield '{"error":"VOICE_UNAVAILABLE"}\n'
