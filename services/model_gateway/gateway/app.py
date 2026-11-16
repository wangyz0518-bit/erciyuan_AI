import asyncio
import hashlib
import hmac
import json
import sqlite3
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Literal

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response, StreamingResponse
from pydantic import BaseModel, ConfigDict, Field

from .providers import PERSONAS, ProviderError, Providers, Settings
from .speech_pool import SpeechPool
from .streaming import StreamingService
from .voice_profiles import VoiceProfiles, register as register_voices


class HistoryItem(BaseModel):
    model_config = ConfigDict(extra='forbid')
    role: Literal['user', 'assistant']
    content: str = Field(min_length=1, max_length=6000)


class ChatInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    request_id: str = Field(pattern=r'^[a-zA-Z0-9_-]{16,100}$')
    character_id: Literal['xing', 'yue']
    content: str = Field(min_length=1, max_length=2000)
    history: list[HistoryItem] = Field(default_factory=list, max_length=20)


class SpeechInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    request_id: str = Field(pattern=r'^[a-zA-Z0-9_-]{16,100}$')
    reply_request_id: str = Field(pattern=r'^[a-zA-Z0-9_-]{16,100}$')
    character_id: Literal['xing', 'yue']
    expression: Literal['calm', 'happy', 'comfort', 'curious'] = 'calm'


class Ledger:
    """24-hour development request replay; never stores provider keys/history."""
    def __init__(self, directory):
        Path(directory).mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(Path(directory) / 'requests.sqlite'), check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute('CREATE TABLE IF NOT EXISTS requests (id TEXT PRIMARY KEY, fingerprint TEXT, '
                        'kind TEXT, character TEXT, status TEXT, text TEXT, audio BLOB, code TEXT, created REAL)')
        self.db.execute("UPDATE requests SET status='failed', code='SERVER_RESTARTED' WHERE status='running'")
        self.db.commit()

    def get(self, rid):
        return self.db.execute('SELECT * FROM requests WHERE id=?', (rid,)).fetchone()

    def claim(self, data, kind):
        self.db.execute('DELETE FROM requests WHERE created<? AND status!=?', (time.time() - 86400, 'running'))
        fingerprint = hashlib.sha256(json.dumps(data, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
        existing = self.get(data['request_id'])
        if existing:
            if existing['fingerprint'] != fingerprint or existing['kind'] != kind:
                raise HTTPException(409, 'REQUEST_ID_CONFLICT')
            return False
        if self.db.execute('SELECT COUNT(*) FROM requests').fetchone()[0] >= 200:
            raise HTTPException(503, 'LOCAL_CAPACITY_REACHED')
        self.db.execute('INSERT INTO requests VALUES (?,?,?,?,?,?,?,?,?)',
                        (data['request_id'], fingerprint, kind, data['character_id'], 'running', '', None, '', time.time()))
        self.db.commit()
        return True

    def finish(self, rid, status, text='', audio=None, code=''):
        self.db.execute('UPDATE requests SET status=?,text=?,audio=?,code=? WHERE id=? AND status=?',
                        (status, text, audio, code, rid, 'running'))
        self.db.commit()


class Job:
    def __init__(self):
        self.events = []
        self.changed = asyncio.Event()
        self.task = None

    def emit(self, event, **data):
        self.events.append({'event': event, **data})
        self.changed.set()


def create_app(settings=None, providers=None, speech_pool=None, enrollment=None):
    settings = settings or Settings.env()
    if settings.mode not in ('mock', 'live') or len(settings.token) < 24:
        raise RuntimeError('Set GATEWAY_MODE=live/mock and a GATEWAY_TOKEN of at least 24 characters.')
    providers = providers or Providers(settings)
    ledger = Ledger(settings.data_dir)
    jobs: dict[str, Job] = {}
    streaming = StreamingService(settings, providers, speech_pool or SpeechPool(settings), ChatInput)
    voice_profiles=VoiceProfiles(settings,streaming.pool,enrollment)
    streaming.voice_profiles=voice_profiles
    voice_profiles.chat_busy=lambda: bool(streaming.tasks) or any(j.task and not j.task.done() for j in jobs.values())

    @asynccontextmanager
    async def lifespan(app):
        await voice_profiles.start()
        yield
        tasks = [j.task for j in jobs.values() if j.task and not j.task.done()]
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        await voice_profiles.close()
        await streaming.close()
        if hasattr(providers, 'close'):
            await providers.close()
        ledger.db.close()

    app = FastAPI(title='Companion model gateway (local development)', version='0.1.0', lifespan=lifespan)
    app.state.ledger = ledger
    app.state.streaming = streaming
    app.state.voice_profiles=voice_profiles
    app.add_api_websocket_route('/v2/conversations/{conversation_id}/stream', streaming.endpoint)

    async def auth(authorization: str = Header(default='')):
        if not hmac.compare_digest(authorization, 'Bearer ' + settings.token):
            raise HTTPException(401, 'UNAUTHORIZED')

    register_voices(app,voice_profiles,auth)

    @app.exception_handler(HTTPException)
    async def http_error(request, exc):
        return JSONResponse({'error': {'code': str(exc.detail), 'message': '请求未完成，请检查状态后重试。'}}, status_code=exc.status_code)

    @app.exception_handler(RequestValidationError)
    async def validation_error(request, exc):
        # Pydantic errors contain user input: don't echo it.
        return JSONResponse({'error': {'code': 'INVALID_REQUEST', 'message': '请求格式不正确。'}}, status_code=422)

    @app.get('/health')
    async def health():
        return {'status': 'ok', 'mode': settings.mode, 'protocols': [1, 2], 'asr': 'not_implemented',
                'chat_configured': bool(settings.deepseek_key),
                'voice_configured': bool(settings.dashscope_key and settings.voice)}

    def claim(data, kind):
        if not ledger.get(data['request_id']) and sum(not j.task.done() for j in jobs.values()) >= 4:
            raise HTTPException(429, 'TOO_MANY_REQUESTS')
        fresh = ledger.claim(data, kind)
        # Finished tasks can be replayed from SQLite without keeping streams forever.
        for rid in list(jobs):
            if jobs[rid].task.done() and rid != data['request_id']:
                del jobs[rid]
        return fresh

    async def run_chat(data, job):
        rid = data.request_id
        job.emit('message.started', request_id=rid)
        text = ''
        try:
            async with asyncio.timeout(90):
                async for delta in providers.reply(data.character_id, [h.model_dump() for h in data.history], data.content):
                    text += delta
                    if len(text) > 6000 or len(job.events) > 8000:
                        raise ProviderError('MODEL_REPLY_TOO_LONG')
                    job.emit('message.delta', delta=delta)
                if not text.strip():
                    raise ProviderError('MODEL_EMPTY')
                ledger.finish(rid, 'completed', text=text)
                job.emit('message.completed', content=text, request_id=rid)
        except asyncio.CancelledError:
            ledger.finish(rid, 'cancelled', code='CANCELLED')
            job.emit('message.cancelled', code='CANCELLED')
        except Exception as exc:
            code = exc.code if isinstance(exc, ProviderError) else 'MODEL_TIMEOUT' if isinstance(exc, TimeoutError) else 'MODEL_UNAVAILABLE'
            ledger.finish(rid, 'failed', code=code)
            job.emit('message.failed', code=code)

    @app.post('/v1/conversations/{conversation_id}/messages', dependencies=[Depends(auth)])
    async def chat(conversation_id: str, data: ChatInput, request: Request):
        if conversation_id != 'local-' + data.character_id or not data.content.strip():
            raise HTTPException(422, 'INVALID_CONVERSATION')
        # History belongs to this device's selected role. This local PoC is not a multi-user API.
        if sum(len(h.content) for h in data.history) > 24000:
            raise HTTPException(422, 'HISTORY_TOO_LONG')
        fresh = claim(data.model_dump(), 'chat')
        if fresh:
            job = jobs[data.request_id] = Job()
            job.task = asyncio.create_task(run_chat(data, job))
        else:
            job = jobs.get(data.request_id)

        async def stream():
            try:
                if job:
                    index = 0
                    while True:
                        job.changed.clear()
                        for packet in job.events[index:]:
                            yield 'data: ' + json.dumps(packet, ensure_ascii=False) + '\n\n'
                            index += 1
                        if job.task.done():
                            break
                        try:
                            await asyncio.wait_for(job.changed.wait(), 5)
                        except TimeoutError:
                            yield ': keepalive\n\n'
                else:
                    row = ledger.get(data.request_id)
                    event = 'message.completed' if row['status'] == 'completed' else 'message.cancelled' if row['status'] == 'cancelled' else 'message.failed'
                    yield 'data: ' + json.dumps({'event': event, 'request_id': data.request_id,
                                                'content': row['text'], 'code': row['code']}, ensure_ascii=False) + '\n\n'
            finally:
                # Disconnect cancels upstream best-effort; no transparent paid retry.
                if job and not job.task.done():
                    job.task.cancel()
                    ledger.finish(data.request_id, 'cancelled', code='CANCELLED')
        return StreamingResponse(stream(), media_type='text/event-stream', headers={'Cache-Control': 'no-store'})

    async def run_speech(data, text, job):
        try:
            selected=voice_profiles.selected(data.character_id,data.request_id)
            async with asyncio.timeout(90):
                audio = (await providers.speech_for_voice(text,selected['provider_id']) if selected
                         else await providers.speech(text, data.character_id, data.expression))
            ledger.finish(data.request_id, 'completed', audio=audio)
        except asyncio.CancelledError:
            ledger.finish(data.request_id, 'cancelled', code='CANCELLED')
        except Exception as exc:
            code = exc.code if isinstance(exc, ProviderError) else 'VOICE_TIMEOUT' if isinstance(exc, TimeoutError) else 'VOICE_UNAVAILABLE'
            ledger.finish(data.request_id, 'failed', code=code)

    @app.post('/v1/audio/speech', dependencies=[Depends(auth)])
    async def speech(data: SpeechInput, request: Request):
        reply = ledger.get(data.reply_request_id)
        if not reply or reply['kind'] != 'chat' or reply['status'] != 'completed' or reply['character'] != data.character_id:
            raise HTTPException(409, 'COMPLETED_REPLY_REQUIRED')
        fresh = claim(data.model_dump(), 'speech')
        if fresh:
            job = jobs[data.request_id] = Job()
            job.task = asyncio.create_task(run_speech(data, reply['text'], job))
        else:
            job = jobs.get(data.request_id)
        if job:
            try:
                while not job.task.done():
                    if await request.is_disconnected():
                        job.task.cancel()
                        ledger.finish(data.request_id, 'cancelled', code='CANCELLED')
                        break
                    await asyncio.sleep(.05)
            except asyncio.CancelledError:
                job.task.cancel()
                ledger.finish(data.request_id, 'cancelled', code='CANCELLED')
                raise
        row = ledger.get(data.request_id)
        if row['status'] != 'completed':
            raise HTTPException(409 if row['status'] == 'cancelled' else 502, row['code'])
        return Response(row['audio'], media_type='audio/wav', headers={'Cache-Control': 'no-store'})

    @app.post('/v1/requests/{request_id}/cancel', dependencies=[Depends(auth)])
    async def cancel(request_id: str):
        row = ledger.get(request_id)
        if not row:
            raise HTTPException(404, 'REQUEST_NOT_FOUND')
        if row['status'] == 'running':
            if request_id in jobs:
                jobs[request_id].task.cancel()
            ledger.finish(request_id, 'cancelled', code='CANCELLED')
        return {'request_id': request_id, 'status': ledger.get(request_id)['status']}

    @app.post('/v1/audio/transcriptions', dependencies=[Depends(auth)])
    async def transcription():
        # No file accepted/read/stored or uploaded to any model in this version.
        raise HTTPException(501, 'ASR_NOT_IMPLEMENTED')

    return app
