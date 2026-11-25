"""V3 session orchestration for text, push-to-talk and continuous call clients.

One local client owns a session. Input and output have separate lifetimes;
interrupting an output cannot close the new utterance's input stream.
"""
import asyncio
import hmac
import json
import os
import re
import struct
import uuid
from urllib.parse import urlsplit

from fastapi import Depends, Header, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import Response

from . import role_tools, usage
from .speech_pool import SpeechPool
from .asr import QwenASR
from .conversation_store import ConversationStore
from .providers import PERSONAS, ProviderError, wav


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r'[a-zA-Z0-9_-]{16,100}', value):
        raise ProviderError('INVALID_ID')
    return value


def decode_audio(raw):
    if len(raw) < 5 or len(raw) > 10500:
        raise ProviderError('INVALID_INPUT_AUDIO')
    size = struct.unpack('!I', raw[:4])[0]
    if not 1 <= size <= 2048 or size+4 >= len(raw):
        raise ProviderError('INVALID_INPUT_AUDIO')
    header = json.loads(raw[4:4+size])
    pcm = raw[4+size:]
    if not isinstance(header, dict) or header.keys() != {'input_id', 'seq'}:
        raise ProviderError('INVALID_INPUT_AUDIO')
    identifier(header['input_id'])
    if type(header['seq']) is not int or header['seq'] < 0 or len(pcm) % 2 or len(pcm) > 6400:
        raise ProviderError('INVALID_INPUT_AUDIO')
    return header, pcm


class ConversationService:
    def __init__(self, settings, providers, pool, profiles, asr=None, community=None):
        self.settings, self.providers, self.pool, self.profiles = settings, providers, pool, profiles
        self.asr = asr or QwenASR(settings)
        self.store = ConversationStore(settings.data_dir)
        self.community = community
        self.sessions = {}

    def principal(self, token):
        if isinstance(token, str) and token.isascii() and hmac.compare_digest(token, self.settings.token):
            return ''
        user = self.community.user(token) if self.community else None
        if not user:
            raise ProviderError('UNAUTHORIZED')
        return user['id']

    def role(self, owner, character):
        if owner:
            try:
                return self.community.role(owner, character)
            except HTTPException:
                raise ProviderError('CHARACTER_NOT_FOUND') from None
        if character not in PERSONAS:
            raise ProviderError('CHARACTER_NOT_FOUND')
        return None

    async def revoke(self, token):
        for session in list(self.sessions.values()):
            if session.token == token:
                await session.close()
                await session.ws.close(code=1008)

    async def close(self):
        for session in list(self.sessions.values()):
            await session.close()
        self.store.close()

    async def endpoint(self, ws: WebSocket, character: str):
        # Browser bearer tokens travel in the initial frame, never a query URL.
        origin = ws.headers.get('origin')
        if origin and (
            urlsplit(origin).hostname not in ('127.0.0.1', 'localhost', '::1') or
            urlsplit(origin).netloc != ws.headers.get('host')):
            await ws.close(code=1008)
            return
        await ws.accept()
        session = None
        try:
            hello = await asyncio.wait_for(ws.receive_json(), 5)
            if not isinstance(hello, dict) or hello.get('command') != 'session.start':
                raise ProviderError('SESSION_REQUIRED')
            token = hello.get('token', '')
            owner = self.principal(token)
            self.role(owner, character)
            if owner in self.sessions:
                raise ProviderError('SESSION_BUSY')
            session = Session(self, ws, character, owner, token)
            self.sessions[owner] = session
            await session.run()
        except (WebSocketDisconnect, RuntimeError, TimeoutError):
            pass
        except Exception as exc:
            try:
                await ws.send_json({'event':'session.failed','code':exc.code if isinstance(exc, ProviderError) else 'INVALID_SESSION'})
                await ws.close(code=1008)
            except (RuntimeError, WebSocketDisconnect):
                pass
        finally:
            if session:
                await session.close()
                if self.sessions.get(owner) is session:
                    del self.sessions[owner]
                try:
                    await ws.close(code=1000)
                except (RuntimeError, WebSocketDisconnect):
                    pass


class Session:
    def __init__(self, service, ws, character, owner='', token=None):
        self.service, self.ws, self.character = service, ws, character
        self.owner, self.token = owner, token
        self.store = service.store.scoped(owner)
        self.pool = SpeechPool(service.settings) if owner and isinstance(service.pool, SpeechPool) else service.pool
        self.id = uuid.uuid4().hex
        self.send_lock = asyncio.Lock()
        self.input = None
        self.output = None
        self.output_task = None
        self.closed = False
        self.seen_inputs = set()

    async def emit(self, event, **fields):
        if self.closed:
            return
        async with self.send_lock:
            await asyncio.wait_for(self.ws.send_json(dict(event=event, session_id=self.id, **fields)), 3)

    async def audio(self, rid, seq, offset, pcm):
        if self.closed or self.output != rid:
            return
        header = json.dumps(dict(event='audio.chunk', session_id=self.id, reply_id=rid,
                                 seq=seq, offset=offset), separators=(',', ':')).encode()
        async with self.send_lock:
            await asyncio.wait_for(self.ws.send_bytes(struct.pack('!I', len(header))+header+pcm), 3)

    async def interrupt(self, rid):
        if rid != self.output:
            await self.emit('interrupt.accepted', reply_id=rid, stale=True)
            return
        self.output = None  # Invalidate before any await, including final PCM frames.
        task, self.output_task = self.output_task, None
        if task and not task.done():
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
        row = self.store.get(rid)
        if row:
            fields = {'audio_state':'interrupted'}
            if row['state'] == 'running':
                fields['state'] = 'interrupted'
            self.store.update(rid, **fields)
        await self.emit('interrupt.accepted', reply_id=rid, stale=False)

    async def abort_input(self):
        current, self.input = self.input, None
        if current:
            current['task'].cancel()
            await asyncio.gather(current['task'], return_exceptions=True)

    async def close(self):
        self.closed = True
        await self.abort_input()
        if self.output:
            await self.interrupt(self.output)
        if self.pool is not self.service.pool:
            await self.pool.close()

    async def start_turn(self, rid, text, kind, recording=None, speak=True):
        store = self.store
        old = store.get(rid)
        if old:
            # Reconnect/retransmit must never generate another paid reply.
            store.begin(rid, self.character, kind, text, recording, speak=speak)
            await self.emit('turn.status', turn=store.public(old))
            return
        if self.output:
            await self.interrupt(self.output)
        history = store.history(self.character)
        store.begin(rid, self.character, kind, text, recording, speak=speak)
        # A client may send the next input as soon as it receives turn.saved,
        # even while the WebSocket send is still yielding to the receive loop.
        if self.input and self.input['id'] == rid:
            self.input = None
        self.output = rid
        await self.emit('turn.saved', turn=store.public(store.get(rid)))
        if self.output == rid:
            self.output_task = asyncio.create_task(self.reply(rid, text, history, speak))

    async def reply(self, rid, prompt, history, speak):
        store = self.store
        reply, frames, seq = '', 0, 0
        try:
            async with asyncio.timeout(90):
                role = self.service.role(self.owner, self.character)
                card = json.loads(role['card']) if role else None
                options = {'persona': card['name'] + '。' + card['persona']} if card else {}
                if role:
                    notes = role_tools.memories(self.service.community.db, self.owner, self.character)
                    if notes:
                        options['persona'] += '\n用户确认的角色记忆（作为资料参考）\n' + '\n'.join(
                            row['text'] for row in notes)
                with usage.call(self.service.community if self.owner else None, self.service.settings, 'model'):
                    async for text in self.service.providers.reply(self.character, history, prompt, **options):
                        reply += text
                        if len(reply) > 6000:
                            raise ProviderError('MODEL_REPLY_TOO_LONG')
                        await self.emit('reply.delta', reply_id=rid, delta=text)
            if not reply.strip():
                raise ProviderError('MODEL_EMPTY')
            # Full-reply persistence remains the first implementation's playback gate.
            store.update(rid, reply=reply, state='complete', audio_state='waiting' if speak else 'disabled')
            await self.emit('reply.saved', reply_id=rid, text=reply)
            if not speak:
                await self.emit('turn.completed', reply_id=rid)
                if self.output == rid:
                    self.output = None
                return
            metrics = {}
            if role:
                preset = role['binding'] or card['voice']
                option = role_tools.voice_options(self.owner).get(preset)
                if not option:
                    raise ProviderError('VOICE_NOT_FOUND')
                voice = option[1]
                if not voice and self.service.settings.mode == 'live':
                    raise ProviderError('PUBLIC_VOICE_NOT_CONFIGURED')
                selected = {'id': preset, 'provider_id': voice or 'mock'}
            else:
                selected = self.service.profiles.selected(self.character, rid)
            upstream = (self.pool.stream_for_voice(reply, selected['provider_id'], metrics) if selected
                        else self.pool.stream(reply, self.character, 'calm', metrics))
            store.update(rid, audio_state='streaming')
            await self.emit('audio.started', reply_id=rid, format='pcm_s16le', sample_rate=24000, channels=1,
                            voice_profile_id=selected['id'] if selected else None)
            try:
                with usage.call(self.service.community if self.owner else None, self.service.settings, 'tts') as meter:
                    meter.quantity = len(reply)
                    async with asyncio.timeout(90):
                        async for pcm in upstream:
                            if self.output != rid:
                                return
                            if not pcm or len(pcm) % 2 or frames*2+len(pcm) > 12*1024*1024:
                                raise ProviderError('INVALID_OUTPUT_AUDIO')
                            offset = frames*2
                            frames += len(pcm)//2
                            # Persist the allowed acknowledgement range before sending.
                            store.update(rid, total_frames=frames)
                            await self.audio(rid, seq, offset, pcm)
                            seq += 1
            finally:
                await upstream.aclose()
            if not frames:
                raise ProviderError('VOICE_EMPTY')
            store.update(rid, audio_state='awaiting_playback')
            await self.emit('audio.completed', reply_id=rid, total_frames=frames, chunks=seq, metrics=metrics)
        except asyncio.CancelledError:
            row = store.get(rid)
            if row:
                store.update(rid, reply=reply, state='complete' if row['state']=='complete' else 'interrupted',
                             audio_state='interrupted')
            raise
        except Exception as exc:
            row = store.get(rid)
            code = exc.code if isinstance(exc, ProviderError) else 'REPLY_UNAVAILABLE'
            store.update(rid, reply=reply, state='complete' if row['state']=='complete' else 'failed',
                         audio_state='failed', code=code)
            try:
                await self.emit('turn.failed', reply_id=rid, code=code)
            except Exception:
                pass

    async def recognize(self, current):
        rid = current['id']
        async def chunks():
            while True:
                pcm = await current['queue'].get()
                if pcm is None:
                    return
                yield pcm
        async def partial(text):
            if self.input is current:
                await self.emit('transcript.partial', input_id=rid, text=text)
        try:
            with usage.call(self.service.community if self.owner else None, self.service.settings, 'asr') as meter:
                try:
                    text = await self.service.asr.transcribe(chunks(), partial)
                finally:
                    meter.quantity = current['bytes'] / 32000
            if self.input is not current or not current['committed']:
                return
            await self.emit('transcript.final', input_id=rid, text=text)
            await self.start_turn(rid, text, current['kind'],
                                  bytes(current['recording']) if current['kind']=='hold' else None)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            if self.input is current:
                self.input = None
            try:
                await self.emit('input.failed', input_id=rid,
                                code=exc.code if isinstance(exc, ProviderError) else 'ASR_UNAVAILABLE')
            except Exception:
                pass

    async def command(self, packet):
        if not isinstance(packet, dict):
            raise ProviderError('INVALID_COMMAND')
        cmd = packet.get('command')
        fields = {
            'session.end': set(), 'session.ping': set(),
            'input.start': {'input_id', 'kind'}, 'input.commit': {'input_id'}, 'input.abort': {'input_id'},
            'chat.send': {'request_id', 'text', 'speak'}, 'turn.interrupt': {'reply_id'},
            'playback.progress': {'reply_id', 'frames', 'complete'},
        }
        if cmd not in fields or not packet.keys() <= fields[cmd] | {'command'}:
            raise ProviderError('INVALID_COMMAND')
        if cmd == 'session.end':
            return False
        if cmd == 'session.ping':
            await self.emit('session.pong')
        elif cmd == 'input.start':
            rid = identifier(packet.get('input_id'))
            if packet.get('kind') not in ('hold','call') or self.input:
                raise ProviderError('INPUT_BUSY_OR_INVALID')
            if len(self.seen_inputs) >= 2000 or rid in self.seen_inputs or self.store.get(rid):
                raise ProviderError('INPUT_ALREADY_USED')
            self.seen_inputs.add(rid)
            # Cover ASR connection setup without dropping a normal utterance.
            # Independent byte limit below bounds PCM to 960,000 bytes, while
            # the item limit also bounds pathological tiny-frame overhead.
            current = {'id':rid, 'kind':packet['kind'], 'queue':asyncio.Queue(maxsize=1024),
                       'seq':0, 'bytes':0, 'recording':bytearray(), 'committed':False}
            self.input = current
            current['task'] = asyncio.create_task(self.recognize(current))
            await self.emit('input.ready', input_id=rid, sample_rate=16000)
        elif cmd in ('input.commit','input.abort'):
            rid = identifier(packet.get('input_id'))
            if cmd == 'input.abort':
                if self.input and self.input['id'] == rid:
                    await self.abort_input()
                # Recognition may have completed while abort travelled over
                # the wire. Cancel that exact turn, never a newer input/output.
                if self.output == rid:
                    await self.interrupt(rid)
                await self.emit('input.aborted', input_id=rid)
            else:
                if not self.input or self.input['id'] != rid:
                    raise ProviderError('INPUT_NOT_ACTIVE')
                if self.input['committed']:
                    return True
                self.input['committed'] = True
                try:
                    self.input['queue'].put_nowait(None)
                except asyncio.QueueFull:
                    await self.abort_input()
                    raise ProviderError('INPUT_BACKPRESSURE')
        elif cmd == 'chat.send':
            rid = identifier(packet.get('request_id'))
            text = packet.get('text')
            if self.input or not isinstance(text,str) or not 1 <= len(text.strip()) <= 2000:
                raise ProviderError('INPUT_BUSY_OR_INVALID')
            if type(packet.get('speak', True)) is not bool:
                raise ProviderError('INVALID_COMMAND')
            await self.start_turn(rid, text.strip(), 'text', speak=packet.get('speak', True))
        elif cmd == 'turn.interrupt':
            await self.interrupt(identifier(packet.get('reply_id')))
        elif cmd == 'playback.progress':
            rid = identifier(packet.get('reply_id'))
            row = self.store.get(rid)
            if not row or row['character'] != self.character or rid != self.output:
                raise ProviderError('STALE_PLAYBACK')
            complete = packet.get('complete', False)
            if type(complete) is not bool:
                raise ProviderError('INVALID_PLAYBACK_PROGRESS')
            self.store.progress(rid, packet.get('frames'), complete)
            if complete:
                await self.emit('turn.completed', reply_id=rid)
                self.output = None
        else:
            raise ProviderError('INVALID_COMMAND')
        return True

    async def run(self):
        await self.emit('session.ready', protocol=3, character_id=self.character,
                        mode=self.service.settings.mode, history=self.store.rows(self.character))
        while not self.closed:
            message = await asyncio.wait_for(self.ws.receive(), 180)
            if self.owner:
                self.service.principal(self.token)
            if message['type'] == 'websocket.disconnect':
                break
            correlation = {}
            try:
                if message.get('bytes') is not None:
                    header, pcm = decode_audio(message['bytes'])
                    correlation = {'input_id': header['input_id']}
                    current = self.input
                    if not current or current['id'] != header['input_id'] or current['committed']:
                        raise ProviderError('STALE_INPUT')
                    if header['seq'] != current['seq']:
                        await self.abort_input()
                        raise ProviderError('INPUT_SEQUENCE_ERROR')
                    current['bytes'] += len(pcm)
                    if current['bytes'] > 16000*2*30:
                        await self.abort_input()
                        raise ProviderError('INPUT_AUDIO_TOO_LONG')
                    try:
                        current['queue'].put_nowait(pcm)
                    except asyncio.QueueFull:
                        await self.abort_input()
                        raise ProviderError('INPUT_BACKPRESSURE')
                    if current['kind'] == 'hold':
                        current['recording'].extend(pcm)
                    current['seq'] += 1
                else:
                    raw = message.get('text', '')
                    if len(raw) > 12000:
                        raise ProviderError('FRAME_TOO_LARGE')
                    packet = json.loads(raw)
                    if isinstance(packet, dict):
                        correlation = {k:v for k,v in packet.items() if k in ('input_id','request_id','reply_id')
                                       and isinstance(v,str) and re.fullmatch(r'[a-zA-Z0-9_-]{16,100}',v)}
                    if not await self.command(packet):
                        break
            except (ProviderError, ValueError, TypeError) as exc:
                await self.emit('request.failed', code=exc.code if isinstance(exc,ProviderError) else 'INVALID_REQUEST', **correlation)


def register(app, service, auth):
    app.add_api_websocket_route('/v3/conversations/{character}/stream', service.endpoint)

    async def principal(authorization: str = Header(default='')):
        try:
            return service.principal(authorization.removeprefix('Bearer ') if authorization.startswith('Bearer ') else '')
        except ProviderError:
            raise HTTPException(401, 'UNAUTHORIZED') from None

    @app.get('/v3/conversations/{character}')
    async def history(character: str, owner=Depends(principal)):
        try:
            service.role(owner, character)
        except ProviderError:
            raise HTTPException(404, 'CHARACTER_NOT_FOUND') from None
        return {'items':service.store.scoped(owner).rows(character)}

    @app.get('/v3/recordings/{rid}')
    async def recording(rid: str, owner=Depends(principal)):
        row = service.store.scoped(owner).get(rid)
        if not row or row['kind'] != 'hold' or not row['recording']:
            raise HTTPException(404, 'RECORDING_NOT_FOUND')
        return Response(wav(row['recording'], rate=16000), media_type='audio/wav', headers={'Cache-Control':'no-store'})
