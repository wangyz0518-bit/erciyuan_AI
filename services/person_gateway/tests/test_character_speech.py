import asyncio
import base64
import hashlib
import json
import sqlite3
from contextlib import closing

import httpx
import pytest
from fastapi import HTTPException

from character_speech import CharacterSpeech
from gateway import Settings, create_app


def test_character_speech_in_completed_turn(tmp_path):
    async def run():
        token = "t" * 32
        headers = {"Authorization": "Bearer " + token}
        owner = "local-dev-owner"
        rid = "speech-integration-001"
        app = create_app(Settings(
            local_tokens={token: owner, "b"*32: "another"},
            character_allowlist={owner: {"star", "moon"}, "another": {"star"}},
            ledger_path=str(tmp_path / "gateway.sqlite"),
        ), speech=CharacterSpeech(mode="demo"))
        ledger = app.state.ledger
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://app") as client:
            samples = []
            for role in ["star", "moon"]:
                path = f"/v1/characters/{role}/turns/{rid}/speech"
                assert (await client.post(path, headers=headers)).status_code == 404
                await ledger.claim(owner, role, rid, "test")
                assert (await client.post(path, headers=headers)).status_code == 409
                await ledger.finish(owner, role, rid, "completed", content="回复已经保存在本人物时间线。")
                assert (await client.post(path)).status_code == 401
                assert (await client.post(path, headers={"Authorization": "Bearer " + "b"*32})).status_code in (403, 404)
                response = await client.post(path, headers=headers)
                assert response.status_code == 200 and response.headers["x-voice-mode"] == "demo"
                frames = [json.loads(line) for line in response.text.splitlines()]
                assert frames[-1] == {"done": True}
                samples.append(b"".join(base64.b64decode(f["pcm"]) for f in frames[:-1]))
                assert len(samples[-1]) == 28800
                assert (await client.post(path, headers=headers)).status_code == 409
                assert (await ledger.status(owner, role, rid))["status"] == "completed"
            assert samples[0] != samples[1]
        ledger.close()
    asyncio.run(run())


def test_poc_catalog_binding_scope_and_role(tmp_path):
    path = tmp_path / "catalog.sqlite"
    key = "fixture"
    scope = hashlib.sha256(json.dumps(["live", CharacterSpeech.model, "", key]).encode()).hexdigest()
    with closing(sqlite3.connect(path)) as db:
        db.executescript("CREATE TABLE profiles(id, provider_id, scope, status); CREATE TABLE bindings(character, profile);")
        for role in ("xing", "yue"):
            db.execute("INSERT INTO profiles VALUES(?,?,?,?)", (role, "clone-" + role, scope, "ready"))
            db.execute("INSERT INTO bindings VALUES(?,?)", (role, role))
        db.commit()
    synth = CharacterSpeech("live", key, catalog=str(path))
    assert synth.binding("local-dev-owner", "star") == "clone-xing"
    assert synth.binding("local-dev-owner", "moon") == "clone-yue"
    with pytest.raises(HTTPException):
        synth.binding("different-owner", "star")
    with pytest.raises(HTTPException):
        CharacterSpeech("live", "wrong", catalog=str(path), star_voice="default").binding("local-dev-owner", "star")
    with closing(sqlite3.connect(path)) as db:
        db.execute("DELETE FROM bindings WHERE character='yue'")
        db.commit()
    defaults = CharacterSpeech("live", key, catalog=str(path), moon_voice="explicit-moon")
    assert defaults.binding("local-dev-owner", "moon") == "explicit-moon"
    assert defaults.binding("local-dev-owner", "star") == "clone-xing"
    with pytest.raises(HTTPException):
        synth.binding("local-dev-owner", "moon")


def test_cosyvoice_wire_protocol_with_fake_socket(monkeypatch):
    class Socket:
        def __init__(self):
            self.commands = []
            self.frames = iter(["task-started", b"\x01", b"\x02\x03\x04", "task-finished"])
            self.closed = False

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_):
            self.closed = True

        async def send(self, packet):
            self.commands.append(json.loads(packet))

        async def recv(self):
            item = next(self.frames)
            if isinstance(item, bytes):
                return item
            task = self.commands[0]["header"]["task_id"]
            return json.dumps({"header": {"event": item, "task_id": task}})

    socket = Socket()
    monkeypatch.setattr("character_speech.connect", lambda *args, **kwargs: socket)

    async def collect():
        synth = CharacterSpeech("live", "fake-key")
        return [json.loads(frame) async for frame in synth.frames("本轮已保存回复", "clone-star")]

    frames = asyncio.run(collect())
    assert frames == [{"pcm": "AQIDBA=="}, {"done": True}]
    assert socket.closed
    start, text, finish = socket.commands
    assert start["payload"]["parameters"]["voice"] == "clone-star"
    assert text["payload"]["input"]["text"] == "本轮已保存回复"
    assert finish["header"]["action"] == "finish-task"
