"""Single-user reusable CosyVoice connection; never share an active task."""
import asyncio
import json
import math
import re
import struct
import time
import uuid

from websockets.asyncio.client import connect

from .providers import ProviderError


class SpeechPool:
    def __init__(self, settings, connector=connect):
        self.settings = settings
        self.connector = connector
        self.lock = asyncio.Lock()
        self.socket = None
        self.last_used = 0.
        self.serial = 0

    async def close(self):
        socket, self.socket = self.socket, None
        if socket:
            await socket.close()

    async def stream(self, text, character, expression, metrics):
        start = time.monotonic()
        try:
            await asyncio.wait_for(self.lock.acquire(), 2)
        except TimeoutError:
            raise ProviderError('VOICE_BUSY') from None
        clean = False
        try:
            s = self.settings
            if s.mode == 'mock':
                metrics.update(reused=self.serial > 0, connection_serial=1)
                self.serial = 1
                await asyncio.sleep(.1)
                for _ in range(20):
                    yield b''.join(struct.pack('<h', int(1800*math.sin(i*2*math.pi*440/24000))) for i in range(2400))
                    await asyncio.sleep(.03)
                clean = True
                return
            voice = (s.voice_yue or s.voice) if character == 'yue' else s.voice
            if not s.dashscope_key or not voice:
                raise ProviderError('VOICE_NOT_CONFIGURED')
            if s.workspace and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]{0,127}', s.workspace):
                raise ProviderError('VOICE_NOT_CONFIGURED')
            if self.socket and time.monotonic()-self.last_used > 45:
                await self.close()
            reused = self.socket is not None
            if not self.socket:
                host = f'{s.workspace}.cn-beijing.maas.aliyuncs.com' if s.workspace else 'dashscope.aliyuncs.com'
                self.socket = await self.connector(f'wss://{host}/api-ws/v1/inference',
                    additional_headers={'Authorization': f'Bearer {s.dashscope_key}'},
                    open_timeout=10, close_timeout=1, max_size=4*1024*1024, proxy=None)
                self.serial += 1
            metrics.update(reused=reused, connection_serial=self.serial,
                           connection_setup_ms=round((time.monotonic()-start)*1000, 2))
            task = uuid.uuid4().hex
            styles = {'calm': '用普通话自然交谈，语气平静，保持日常语速。',
                      'happy': '用普通话带着轻微笑意交谈，保持日常语速。',
                      'comfort': '用普通话温柔安慰，保持自然语速。',
                      'curious': '用普通话自然表达疑惑，保持日常语速。'}
            async def send(action, payload):
                await self.socket.send(json.dumps({'header': {'action': action, 'task_id': task, 'streaming': 'duplex'},
                                                   'payload': payload}, ensure_ascii=False))
            await send('run-task', {'task_group': 'audio', 'task': 'tts', 'function': 'SpeechSynthesizer',
                'model': s.voice_model, 'input': {}, 'parameters': {'text_type': 'PlainText',
                'voice': voice, 'format': 'pcm', 'sample_rate': 24000, 'rate': 1., 'pitch': 1.,
                'instruction': styles[expression]}})
            ready, total, remainder = False, 0, b''
            while True:
                item = await asyncio.wait_for(self.socket.recv(), 30)
                if isinstance(item, bytes):
                    if not ready:
                        raise ProviderError('VOICE_PROTOCOL_ERROR')
                    total += len(item)
                    if total > 12*1024*1024:
                        raise ProviderError('VOICE_TOO_LARGE')
                    joined = remainder+item
                    end = len(joined)-len(joined)%2
                    remainder = joined[end:]
                    if end:
                        metrics.setdefault('first_packet_ms', round((time.monotonic()-start)*1000, 2))
                        for offset in range(0, end, 9600):
                            yield joined[offset:min(end, offset+9600)]
                    continue
                header = json.loads(item).get('header', {})
                if header.get('task_id') != task:
                    raise ProviderError('VOICE_PROTOCOL_ERROR')
                event = header.get('event')
                if event == 'task-started':
                    if ready:
                        raise ProviderError('VOICE_PROTOCOL_ERROR')
                    ready = True
                    await send('continue-task', {'input': {'text': text}})
                    await send('finish-task', {'input': {}})
                elif event == 'task-failed':
                    raise ProviderError('VOICE_UNAVAILABLE')
                elif event == 'task-finished':
                    if not ready or not total or remainder:
                        raise ProviderError('VOICE_INCOMPLETE')
                    clean = True
                    return
        finally:
            try:
                if not clean:
                    await self.close()
            finally:
                self.last_used = time.monotonic()
                self.lock.release()
