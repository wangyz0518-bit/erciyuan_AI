"""Versioned server-orchestrated text + PCM channel; v1 remains unchanged."""
import asyncio
import hashlib
import hmac
import json
from pathlib import Path
import sqlite3
import struct
import time
import uuid

from fastapi import WebSocket, WebSocketDisconnect
from pydantic import BaseModel, ConfigDict, Field

from .providers import ProviderError


class VoiceOption(BaseModel):
    model_config = ConfigDict(extra='forbid')
    enabled: bool = True


class TurnStore:
    def __init__(self, directory):
        Path(directory).mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(Path(directory)/'streaming.sqlite'), check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute('CREATE TABLE IF NOT EXISTS turns (id TEXT PRIMARY KEY, fingerprint TEXT, character TEXT, '
                        'status TEXT, text TEXT, code TEXT, speech_id TEXT, created REAL)')
        self.db.execute('CREATE TABLE IF NOT EXISTS voices (id TEXT PRIMARY KEY, parent TEXT, status TEXT, '
                        'code TEXT, pcm BLOB, created REAL)')
        for table in ('turns', 'voices'):
            self.db.execute(f"UPDATE {table} SET status='failed', code='SERVER_RESTARTED' WHERE status='running'")
        self.db.commit()

    def get(self, table, rid):
        return self.db.execute(f'SELECT * FROM {table} WHERE id=?', (rid,)).fetchone()

    def capacity(self):
        for table in ('turns', 'voices'):
            self.db.execute(f"DELETE FROM {table} WHERE created<? AND status!='running'", (time.time()-86400,))
        self.db.commit()
        count = sum(self.db.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0] for table in ('turns', 'voices'))
        size = self.db.execute('SELECT COALESCE(SUM(length(pcm)),0) FROM voices').fetchone()[0]
        if count >= 200 or size >= 128*1024*1024:
            raise ProviderError('LOCAL_CAPACITY_REACHED')

    def claim(self, data):
        rid = data['request_id']
        fingerprint = hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()
        old = self.get('turns', rid)
        if old:
            if old['fingerprint'] != fingerprint:
                raise ProviderError('REQUEST_ID_CONFLICT')
            return False
        self.capacity()
        self.db.execute('INSERT INTO turns VALUES (?,?,?,?,?,?,?,?)',
                        (rid, fingerprint, data['character_id'], 'running', '', '', '', time.time()))
        self.db.commit()
        return True

    def finish_turn(self, rid, status, text='', code=''):
        self.db.execute("UPDATE turns SET status=?,text=?,code=? WHERE id=? AND status='running'", (status,text,code,rid))
        self.db.commit()

    def voice(self, rid, sid):
        old = self.get('voices', sid)
        if old:
            if old['parent'] != rid:
                raise ProviderError('REQUEST_ID_CONFLICT')
            self.db.execute('UPDATE turns SET speech_id=? WHERE id=?', (sid,rid))
            self.db.commit()
            return False
        self.capacity()
        self.db.execute('INSERT INTO voices VALUES (?,?,?,?,?,?)', (sid,rid,'running','',None,time.time()))
        self.db.execute('UPDATE turns SET speech_id=? WHERE id=?', (sid,rid))
        self.db.commit()
        return True

    def finish_voice(self, sid, status, code='', pcm=None):
        self.db.execute("UPDATE voices SET status=?,code=?,pcm=? WHERE id=? AND status='running'", (status,code,pcm,sid))
        self.db.commit()


class StreamingService:
    def __init__(self, settings, providers, pool, chat_input):
        self.settings, self.providers, self.pool = settings, providers, pool
        self.store = TurnStore(settings.data_dir)
        self.tasks = {}
        self.voice_profiles = None
        class SendInput(chat_input):
            speech: VoiceOption = Field(default_factory=VoiceOption)
        self.input = SendInput

    async def close(self):
        pending = list(self.tasks.values())
        for task in pending:
            task.cancel()
        await asyncio.gather(*pending, return_exceptions=True)
        await self.pool.close()
        self.store.db.close()

    async def endpoint(self, ws: WebSocket, conversation_id: str):
        supplied = ws.headers.get('authorization', '')
        if not hmac.compare_digest(supplied, 'Bearer '+self.settings.token) or conversation_id not in ('local-xing','local-yue'):
            await ws.close(code=1008)
            return
        await ws.accept()
        role = conversation_id[6:]
        lock = asyncio.Lock()
        owned = set()
        muted = set()
        closed = False

        async def emit(event, rid, **fields):
            packet = dict(event=event, request_id=rid, character_id=role, **fields)
            async with lock:
                await asyncio.wait_for(ws.send_json(packet), 5)

        async def chunk(rid, sid, seq, offset, pcm):
            header = json.dumps(dict(event='audio.chunk', request_id=rid, character_id=role,
                                     speech_id=sid, seq=seq, offset=offset), separators=(',', ':')).encode()
            async with lock:
                await asyncio.wait_for(ws.send_bytes(struct.pack('!I',len(header))+header+pcm), 5)

        def ensure_turn(rid):
            row = self.store.get('turns', rid)
            if not row or row['character'] != role:
                raise ProviderError('REQUEST_NOT_FOUND')
            return row

        async def status(rid):
            row = ensure_turn(rid)
            voice = self.store.get('voices', row['speech_id']) if row['speech_id'] else None
            await emit('turn.status', rid, status=row['status'], content=row['text'], code=row['code'],
                       speech_id=row['speech_id'], speech_status=voice['status'] if voice else 'none',
                       speech_code=voice['code'] if voice else '')

        async def speech(rid, sid, text, cached=None):
            metrics = {}
            collected = bytearray()
            seq = 0
            first = True
            try:
                selected=self.voice_profiles.selected(role,sid) if self.voice_profiles and cached is None else None
                if selected:metrics['voice_profile_id']=selected['id']
                async with asyncio.timeout(90):
                    async def audio():
                        if cached is not None:
                            metrics.update(reused=False, cached=True)
                            for i in range(0,len(cached),9600):
                                yield cached[i:i+9600]
                        else:
                            upstream = (self.pool.stream_for_voice(text,selected['provider_id'],metrics) if selected
                                        else self.pool.stream(text,role,'calm',metrics))
                            try:
                                async for part in upstream:
                                    yield part
                            finally:
                                await upstream.aclose()
                    generator = audio()
                    try:
                        async for part in generator:
                            if first:
                                await emit('audio.started',rid,speech_id=sid,format='pcm_s16le',sample_rate=24000,
                                           channels=1, **metrics)
                                first = False
                            await chunk(rid,sid,seq,len(collected),part)
                            collected.extend(part)
                            seq += 1
                    finally:
                        await generator.aclose()
                if not collected:
                    raise ProviderError('VOICE_EMPTY')
                self.store.finish_voice(sid,'completed',pcm=bytes(collected))
                await emit('audio.completed',rid,speech_id=sid,bytes=len(collected),chunks=seq,**metrics)
            except asyncio.CancelledError:
                self.store.finish_voice(sid,'cancelled',code='CANCELLED')
                if not closed:
                    await emit('audio.cancelled',rid,speech_id=sid,code='CANCELLED')
                raise
            except Exception as exc:
                code = exc.code if isinstance(exc,ProviderError) else 'VOICE_TIMEOUT' if isinstance(exc,TimeoutError) else 'VOICE_UNAVAILABLE'
                self.store.finish_voice(sid,'failed',code=code)
                if not closed:
                    await emit('audio.failed',rid,speech_id=sid,code=code)

        async def run_turn(data):
            rid = data['request_id']
            text = ''
            try:
                await emit('message.started',rid)
                async with asyncio.timeout(90):
                    async for delta in self.providers.reply(role,data['history'],data['content']):
                        text += delta
                        if len(text)>6000:
                            raise ProviderError('MODEL_REPLY_TOO_LONG')
                        await emit('message.delta',rid,delta=delta)
                if not text.strip():
                    raise ProviderError('MODEL_EMPTY')
                self.store.finish_turn(rid,'completed',text=text)
                sid = uuid.uuid4().hex if data['speech']['enabled'] and rid not in muted else ''
                if sid:
                    try:
                        self.store.voice(rid,sid)
                    except ProviderError:
                        await emit('message.completed',rid,content=text,speech_id='')
                        await emit('audio.failed',rid,speech_id='',code='LOCAL_CAPACITY_REACHED')
                        return
                await emit('message.completed',rid,content=text,speech_id=sid)
                if sid:
                    await speech(rid,sid,text)
            except asyncio.CancelledError:
                self.store.finish_turn(rid,'cancelled',code='CANCELLED')
                row = self.store.get('turns',rid)
                if row['speech_id']:
                    self.store.finish_voice(row['speech_id'],'cancelled',code='CANCELLED')
                if not closed and self.store.get('turns',rid)['status']=='cancelled':
                    await emit('message.cancelled',rid,code='CANCELLED')
                raise
            except Exception as exc:
                code = exc.code if isinstance(exc,ProviderError) else 'MODEL_TIMEOUT' if isinstance(exc,TimeoutError) else 'MODEL_UNAVAILABLE'
                self.store.finish_turn(rid,'failed',code=code)
                if not closed:
                    await emit('message.failed',rid,code=code)

        def spawn(key, coro):
            task = asyncio.create_task(coro)
            self.tasks[key] = task
            owned.add(key)
            def finished(done):
                if self.tasks.get(key) is done:
                    self.tasks.pop(key,None)
                owned.discard(key)
                muted.discard(key)
                if not done.cancelled():
                    done.exception()  # Transport failures are already persisted, never log payloads.
            task.add_done_callback(finished)

        try:
            await emit('session.ready','',protocol=2)
            while True:
                raw = await ws.receive_text()
                if len(raw)>100000:
                    raise ValueError('FRAME_TOO_LARGE')
                packet = json.loads(raw)
                if not isinstance(packet, dict):
                    raise ValueError('INVALID_FRAME')
                rid = packet.get('request_id','')
                try:
                    if not isinstance(rid,str) or not 16<=len(rid)<=100 or not all(c.isascii() and (c.isalnum() or c in '_-') for c in rid):
                        raise ProviderError('INVALID_REQUEST')
                    command = packet.get('command')
                    if command=='chat.send':
                        data = self.input.model_validate({k:v for k,v in packet.items() if k!='command'}).model_dump()
                        if data['character_id']!=role or not data['content'].strip() or sum(len(h['content']) for h in data['history'])>24000:
                            raise ProviderError('INVALID_REQUEST')
                        if len(self.tasks)>=4 and not self.store.get('turns',rid):
                            raise ProviderError('TOO_MANY_REQUESTS')
                        if self.store.claim(data):
                            spawn(rid,run_turn(data))
                        else:
                            await status(rid)
                    elif command=='turn.status':
                        await status(rid)
                    elif command in ('turn.cancel','speech.cancel'):
                        row = ensure_turn(rid)
                        muted.add(rid)
                        if command=='turn.cancel' or row['status']=='completed':
                            for key in (rid,row['speech_id']):
                                if key in self.tasks:
                                    self.tasks[key].cancel()
                        await emit('cancel.accepted',rid,scope=command)
                    elif command=='speech.retry':
                        row = ensure_turn(rid)
                        if len(self.tasks)>=4:
                            raise ProviderError('TOO_MANY_REQUESTS')
                        sid = packet.get('speech_id','')
                        if not isinstance(sid,str) or not 16<=len(sid)<=100 or not sid.isascii() or not sid.replace('-','').replace('_','').isalnum():
                            raise ProviderError('INVALID_REQUEST')
                        if row['status']!='completed':
                            raise ProviderError('COMPLETED_REPLY_REQUIRED')
                        if self.store.get('turns',sid) or sid in self.tasks:
                            raise ProviderError('REQUEST_ID_CONFLICT')
                        if rid in self.tasks or row['speech_id'] in self.tasks:
                            raise ProviderError('VOICE_BUSY')
                        old = self.store.get('voices',sid)
                        fresh = self.store.voice(rid,sid)
                        if fresh:
                            spawn(sid,speech(rid,sid,row['text']))
                        elif old['status']=='completed':
                            spawn(sid,speech(rid,sid,row['text'],cached=old['pcm']))
                        else:
                            await emit('audio.failed',rid,speech_id=sid,code=old['code'] or 'VOICE_BUSY')
                    else:
                        raise ProviderError('INVALID_COMMAND')
                except Exception as exc:
                    code = exc.code if isinstance(exc,ProviderError) else 'INVALID_REQUEST'
                    await emit('request.failed',rid,code=code)
        except (WebSocketDisconnect,RuntimeError,ValueError,TimeoutError):
            pass
        finally:
            closed = True
            pending = [self.tasks[k] for k in owned if k in self.tasks]
            for task in pending:
                task.cancel()
            await asyncio.gather(*pending,return_exceptions=True)
