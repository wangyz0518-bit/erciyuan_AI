"""Existing v2 protocol client. One operation at a time, no automatic paid retry."""
import asyncio
import json
import struct
import time
import uuid
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit
from urllib.request import ProxyHandler, build_opener

from websockets.asyncio.client import connect

from player import MAX_BYTES, Player
from store import Store


class LabError(Exception):
    pass


def load_config(path):
    data = json.loads(Path(path).read_text(encoding='utf-8-sig'))
    url = data.get('MODEL_GATEWAY_URL', '')
    token = data.get('MODEL_GATEWAY_TOKEN', '')
    parsed = urlsplit(url)
    if (parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.username
            or parsed.password or parsed.query or parsed.fragment or parsed.path not in ('', '/')
            or (parsed.scheme == 'http' and parsed.hostname not in ('127.0.0.1', 'localhost', '::1'))
            or not isinstance(token, str) or len(token) < 24):
        raise LabError('INVALID_CONFIG')
    return url.rstrip('/'), token


def decode(raw):
    pcm = None
    if isinstance(raw, bytes):
        if len(raw) < 4:
            raise LabError('INVALID_AUDIO_FRAME')
        size = struct.unpack('!I', raw[:4])[0]
        if size > 4096 or len(raw) <= size+4:
            raise LabError('INVALID_AUDIO_FRAME')
        packet = json.loads(raw[4:4+size])
        pcm = raw[4+size:]
        if len(pcm) % 2 or len(pcm) > 192000:
            raise LabError('INVALID_PCM')
        if not isinstance(packet, dict) or packet.get('event') != 'audio.chunk':
            raise LabError('INVALID_AUDIO_FRAME')
    else:
        packet = json.loads(raw)
    if not isinstance(packet, dict):
        raise LabError('INVALID_EVENT')
    return packet, pcm


ERRORS = {
    'CONNECTION_LOST': '连接已断开，未自动重发。可手动重试。',
    'CONNECTION_FAILED': '无法连接服务器，请检查网关是否已启动。',
    'REQUEST_NOT_FOUND': '服务器中的原回复已过期；如需新回复，请重新发送。',
    'VOICE_BUSY': '声音服务仍在收尾，请稍后点重试朗读。',
    'LOCAL_CAPACITY_REACHED': '开发服务缓存已满，请联系开发者处理。',
    'LOCAL_SAVE_FAILED': '本地保存失败，已停止声音；请检查磁盘空间。',
    'AUDIO_DEVICE_FAILED': '无法使用所选声音设备，请换一个输出设备重试朗读。',
    'TIMEOUT': '等待超时，未自动重试；已保存的文字保留。',
    'MODEL_TIMEOUT': '主模型回复超时，原提问已保留，可点“重试回复”。',
    'MODEL_UNAVAILABLE': '主模型暂不可用，原提问已保留，可稍后重试。',
    'VOICE_TIMEOUT': '声音服务超时，文字已保留，可点“重试朗读”。',
}


class Client:
    def __init__(self, url, token, path, notify=lambda state: None, player_factory=Player):
        self.url, self.token = url, token
        self.store = Store(path)
        self.notify = notify
        self.player_factory = player_factory
        self.socket = None
        self.socket_role = None
        self.task = None
        self.player = None
        self.role = 'xing'
        self.busy = False
        self.status = '正在检查网关…'
        self.mode = '未连接'
        self.metrics = {}
        self.preview = ''
        self.active_row = None
        self.last_error = ''

    def publish(self):
        self.notify({'role': self.role, 'busy': self.busy, 'status': self.status,
                     'mode': self.mode, 'metrics': dict(self.metrics),
                     'rows': self.store.rows(self.role), 'preview': self.preview,
                     'active_row': self.active_row, 'error': self.last_error})

    async def health(self):
        try:
            def read():
                with build_opener(ProxyHandler({})).open(self.url+'/health', timeout=5) as response:
                    return json.load(response)
            result = await asyncio.to_thread(read)
            if 2 not in result.get('protocols', []):
                raise LabError('V2_REQUIRED')
            self.mode = '真实模型' if result.get('mode') == 'live' else '模拟服务（测试音）'
            self.status = '就绪，输入文字后发送。'
        except Exception:
            self.mode = '未连接'
            self.status = '无法连接 v2 网关。启动服务后可点“检查连接”。'
        self.publish()

    async def select(self, role):
        if self.busy or role not in ('xing', 'yue'):
            return
        self.role = role
        self.preview = ''
        self.metrics = {}
        self.status = '已切换角色；聊天记录独立保存。'
        self.publish()

    async def connection(self):
        if self.socket is not None and self.socket_role == self.role and self.socket.state.name == 'OPEN':
            return
        await self.disconnect()
        parsed = urlsplit(self.url)
        url = urlunsplit(('wss' if parsed.scheme == 'https' else 'ws', parsed.netloc,
                         f'/v2/conversations/local-{self.role}/stream', '', ''))
        try:
            self.socket = await connect(url, additional_headers={'Authorization': 'Bearer '+self.token},
                                        open_timeout=10, close_timeout=1, max_size=256000, proxy=None)
            self.socket_role = self.role
            raw = await asyncio.wait_for(self.socket.recv(), 5)
            packet, _ = decode(raw)
            if packet.get('event') != 'session.ready' or packet.get('protocol') != 2:
                raise LabError('V2_REQUIRED')
        except Exception:
            await self.disconnect()
            raise LabError('CONNECTION_FAILED') from None

    async def disconnect(self):
        socket, self.socket = self.socket, None
        self.socket_role = None
        if socket:
            try:
                await socket.close()
            except Exception:
                pass

    async def command(self, command, rid, **fields):
        if self.socket is None:
            raise LabError('CONNECTION_LOST')
        await self.socket.send(json.dumps(dict(command=command, request_id=rid, **fields), ensure_ascii=False))

    def save_text(self, row, content, state):
        try:
            self.store.text(row, content, state)
        except Exception:
            raise LabError('LOCAL_SAVE_FAILED') from None

    def audio_metrics(self, started, text_at, retry):
        if self.player is None:
            return
        self.metrics.update(self.player.metrics())
        output = self.player.first_output
        if output is not None:
            self.metrics['output_ms'] = (output-started)*1000
            if text_at is not None and not retry:
                self.metrics['text_to_output_ms'] = (output-text_at)*1000
            self.status = '正在朗读…'

    async def run(self, prompt='', *, voice_retry=False, text_retry=False, device=None, started=None):
        if self.busy:
            return
        started = started or time.perf_counter()
        self.busy = True
        self.task = asyncio.current_task()
        self.metrics = {'operation': '重试朗读' if voice_retry else '发送文字'}
        self.preview = self.last_error = ''
        self.status = '正在连接…'
        row_id = None
        rid = uuid.uuid4().hex
        sid = ''
        complete = False
        text_at = None
        reply = ''
        try:
            last = self.store.last(self.role)
            if voice_retry:
                if not last or last['text_state'] != 'complete':
                    raise LabError('COMPLETED_REPLY_REQUIRED')
                rid, row_id, reply = last['request_id'], last['id'], last['reply']
                complete = True
                sid = uuid.uuid4().hex
                self.store.audio(row_id, 'running')
            else:
                if text_retry:
                    if not last or last['text_state'] == 'complete':
                        raise LabError('FAILED_REPLY_REQUIRED')
                    prompt = last['prompt']
                prompt = prompt.strip()
                if not 1 <= len(prompt) <= 2000:
                    raise LabError('INPUT_LENGTH')
                history = self.store.history(self.role, before=last['id'] if text_retry else None)
                try:
                    row_id = self.store.begin(rid, self.role, prompt, retry=last['id'] if text_retry else None)
                except Exception:
                    raise LabError('LOCAL_SAVE_FAILED') from None
            self.active_row = row_id
            self.publish()
            await self.connection()
            if voice_retry:
                await self.command('speech.retry', rid, speech_id=sid)
                self.status = '只重试朗读，不重新请求 DeepSeek。'
            else:
                await self.command('chat.send', rid, character_id=self.role, content=prompt,
                                   history=history, speech={'enabled': True})
                self.status = '等待 DeepSeek 回复…'
            count = total = 0
            audio_started = False
            deadline = time.monotonic()+100
            while True:
                self.audio_metrics(started, text_at, voice_retry)
                self.publish()
                if time.monotonic() > deadline:
                    raise LabError('TIMEOUT')
                try:
                    raw = await asyncio.wait_for(self.socket.recv(), .15)
                except TimeoutError:
                    continue
                packet, pcm = decode(raw)
                if packet.get('request_id') != rid or packet.get('character_id') != self.role:
                    continue  # Cancelled/previous role packets never enter a new player.
                event = packet.get('event')
                if event == 'message.delta' and not complete:
                    reply += packet['delta']
                    if len(reply) > 6000:
                        raise LabError('MODEL_REPLY_TOO_LONG')
                    self.preview = reply
                elif event == 'message.completed' and not complete:
                    if not reply.strip() or packet.get('content') != reply:
                        raise LabError('INCOMPLETE_REPLY')
                    text_at = time.perf_counter()
                    self.metrics['text_ms'] = (text_at-started)*1000
                    # Commit the complete text before opening an audio device.
                    self.save_text(row_id, reply, 'complete')
                    complete = True
                    self.preview = ''
                    sid = packet.get('speech_id', '')
                    if not sid:
                        raise LabError('VOICE_UNAVAILABLE')
                    self.store.audio(row_id, 'running')
                    deadline = time.monotonic()+100
                    self.status = '文字已保存，等待声音…'
                elif event == 'audio.started' and packet.get('speech_id') == sid:
                    if (not complete or audio_started or packet.get('format') != 'pcm_s16le'
                            or packet.get('sample_rate') != 24000 or packet.get('channels') != 1):
                        raise LabError('AUDIO_FORMAT_ERROR')
                    audio_started = True
                    self.metrics.update({k: packet[k] for k in ('reused', 'connection_setup_ms', 'first_packet_ms') if k in packet})
                    try:
                        self.player = self.player_factory(device=device)
                    except Exception:
                        raise LabError('AUDIO_DEVICE_FAILED') from None
                elif event == 'audio.chunk' and packet.get('speech_id') == sid:
                    if not audio_started or pcm is None or packet.get('seq') != count or packet.get('offset') != total:
                        raise LabError('AUDIO_SEQUENCE_ERROR')
                    total += len(pcm)
                    count += 1
                    if total > MAX_BYTES:
                        raise LabError('AUDIO_TOO_LARGE')
                    self.player.feed(pcm)
                elif event == 'audio.completed' and packet.get('speech_id') == sid:
                    if not audio_started or not total or packet.get('bytes') != total or packet.get('chunks') != count:
                        raise LabError('AUDIO_INCOMPLETE')
                    self.player.end()
                    deadline = time.monotonic()+MAX_BYTES/48000+10
                    while not self.player.finished.is_set():
                        if time.monotonic() > deadline:
                            raise LabError('TIMEOUT')
                        self.audio_metrics(started, text_at, voice_retry)
                        self.publish()
                        await asyncio.sleep(.05)
                    self.audio_metrics(started, text_at, voice_retry)
                    self.store.audio(row_id, 'complete')
                    self.status = ('朗读完成。可继续聊天，或重试朗读。' if self.player.first_output is not None
                                   else '播放完成，但未检测到有效出声；请检查输出设备。')
                    break
                elif event in ('message.failed', 'message.cancelled', 'request.failed') or (
                    event in ('audio.failed', 'audio.cancelled') and packet.get('speech_id') == sid):
                    raise LabError(packet.get('code', 'SERVICE_UNAVAILABLE'))
        except asyncio.CancelledError:
            self.audio_metrics(started, text_at, voice_retry)
            self.status = '已停止朗读，文字已保留。' if complete else '已取消回复，可点“重试回复”。'
            self.last_error = 'CANCELLED'
            await self.interrupt(rid, complete)
            if row_id is not None:
                if not complete:
                    self.save_text(row_id, reply, 'cancelled')
                self.store.audio(row_id, 'cancelled')
        except Exception as exc:
            self.audio_metrics(started, text_at, voice_retry)
            code = str(exc) if isinstance(exc, LabError) else 'CONNECTION_LOST'
            self.last_error = code
            self.status = ERRORS.get(code, f'本次未完成（{code}），可手动重试。')
            await self.interrupt(rid, complete)
            try:
                if row_id is not None:
                    if not complete:
                        self.save_text(row_id, reply, 'failed')
                    self.store.audio(row_id, 'failed')
            except Exception:
                self.status = ERRORS['LOCAL_SAVE_FAILED']
        finally:
            if self.player is not None:
                self.player.close()
                self.player = None
            self.busy = False
            self.task = None
            self.preview = ''
            self.active_row = None
            self.publish()

    async def interrupt(self, rid, complete):
        if self.player is not None:
            self.player.close()  # Abort immediately, before any network wait.
        try:
            await asyncio.wait_for(self.command('speech.cancel' if complete else 'turn.cancel', rid), 1)
        except Exception:
            pass
        await self.disconnect()

    async def stop(self):
        task = self.task
        if task is not None and not task.done():
            task.cancel()
            try:
                await task
            except (asyncio.CancelledError, Exception):
                pass

    async def close(self):
        await self.stop()
        await self.disconnect()
        self.store.close()
