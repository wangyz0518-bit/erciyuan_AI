import asyncio
import io
import json
import os
import uuid
import wave
from dataclasses import dataclass
from contextlib import asynccontextmanager

import httpx
from websockets.asyncio.client import connect


class ProviderError(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


@dataclass
class Settings:
    mode: str = 'live'
    token: str = ''
    data_dir: str = '.model-local/gateway'
    deepseek_key: str = ''
    deepseek_model: str = 'deepseek-flash'
    thinking: bool = False
    dashscope_key: str = ''
    workspace: str = ''
    voice: str = ''
    voice_yue: str = ''
    voice_model: str = 'cosyvoice-v3.5-flash'
    voice_proxy: str | None = None

    @classmethod
    def env(cls):
        return cls(
            mode=os.getenv('GATEWAY_MODE', 'live'),
            token=os.getenv('GATEWAY_TOKEN', ''),
            data_dir=os.getenv('GATEWAY_DATA_DIR', '.model-local/gateway'),
            deepseek_key=os.getenv('DEEPSEEK_API_KEY', ''),
            deepseek_model=os.getenv('DEEPSEEK_MODEL', 'deepseek-flash'),
            thinking=os.getenv('DEEPSEEK_THINKING', 'false').lower() == 'true',
            dashscope_key=os.getenv('DASHSCOPE_API_KEY', ''),
            workspace=os.getenv('DASHSCOPE_WORKSPACE_ID', ''),
            voice=os.getenv('COSYVOICE_VOICE_ID', ''),
            voice_yue=os.getenv('COSYVOICE_YUE_VOICE_ID', ''),
            voice_proxy=os.getenv('GATEWAY_VOICE_PROXY') or None,
        )


PERSONAS = {
    'xing': '你是小星，一位温柔的星空旅伴。用自然简短的中文聊天。尊重用户，不冒充真人。不使用Markdown排版。',
    'yue': '你是小月，一位开朗的月光旅伴。用自然简短的中文聊天。尊重用户，不冒充真人。不使用Markdown排版。',
}


class Providers:
    def __init__(self, settings: Settings):
        self.settings = settings
        self._http = None

    @asynccontextmanager
    async def http_client(self):
        if self._http is None:
            self._http = httpx.AsyncClient(timeout=httpx.Timeout(30, connect=10),
                limits=httpx.Limits(max_connections=4, max_keepalive_connections=4, keepalive_expiry=45))
        yield self._http

    async def close(self):
        if self._http is not None:
            await self._http.aclose()
            self._http = None

    async def reply(self, character: str, history: list[dict], content: str):
        s = self.settings
        if s.mode == 'mock':
            for part in ['这是接口模拟回复。', '我记得你刚才说：', content[:100]]:
                await asyncio.sleep(.15)
                yield part
            return
        if not s.deepseek_key:
            raise ProviderError('MODEL_NOT_CONFIGURED')
        messages = [{'role': 'system', 'content': PERSONAS[character]}, *history,
                    {'role': 'user', 'content': content}]
        payload = {'model': s.deepseek_model, 'messages': messages, 'stream': True,
                   'max_tokens': 2048, 'thinking': {'type': 'enabled' if s.thinking else 'disabled'}}
        try:
            async with self.http_client() as client:
                async with client.stream('POST', 'https://api.deepseek.com/chat/completions',
                                         headers={'Authorization': f'Bearer {s.deepseek_key}'}, json=payload) as response:
                    if response.status_code != 200:
                        raise ProviderError('MODEL_AUTH_FAILED' if response.status_code in (401, 403) else 'MODEL_UNAVAILABLE')
                    finished = False
                    async for line in response.aiter_lines():
                        if not line.startswith('data:'):
                            continue
                        raw = line[5:].strip()
                        if raw == '[DONE]':
                            break
                        packet = json.loads(raw)
                        choices = packet.get('choices', [])
                        if not choices:
                            continue
                        choice = choices[0]
                        reason = choice.get('finish_reason')
                        if reason and reason != 'stop':
                            raise ProviderError('MODEL_INCOMPLETE')
                        finished = finished or reason == 'stop'
                        # Never forward or synthesize reasoning_content.
                        text = choice.get('delta', {}).get('content')
                        if text:
                            yield text
                    if not finished:
                        raise ProviderError('MODEL_INCOMPLETE')
        except httpx.TimeoutException:
            raise ProviderError('MODEL_TIMEOUT') from None
        except httpx.HTTPError:
            raise ProviderError('MODEL_UNAVAILABLE') from None

    async def speech(self, text: str, character: str, expression: str) -> bytes:
        s = self.settings
        if s.mode == 'mock':
            # Silent WAV deliberately identifies transport-only tests, not real TTS.
            await asyncio.sleep(.15)
            return wav(bytes(24000 * 2))
        voice = (s.voice_yue or s.voice) if character == 'yue' else s.voice
        if not s.dashscope_key or not voice:
            raise ProviderError('VOICE_NOT_CONFIGURED')
        import re
        if s.workspace and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]{0,127}', s.workspace):
            raise ProviderError('VOICE_NOT_CONFIGURED')
        host = f'{s.workspace}.cn-beijing.maas.aliyuncs.com' if s.workspace else 'dashscope.aliyuncs.com'
        task = uuid.uuid4().hex
        styles = {'calm': '用普通话自然交谈，语气平静，保持日常语速。',
                  'happy': '用普通话带着轻微笑意交谈，保持日常语速。',
                  'comfort': '用普通话温柔安慰，保持自然语速。',
                  'curious': '用普通话自然表达疑惑，保持日常语速。'}
        async with connect(f'wss://{host}/api-ws/v1/inference',
                           additional_headers={'Authorization': f'Bearer {s.dashscope_key}'},
                           open_timeout=15, max_size=4 * 1024 * 1024, proxy=s.voice_proxy) as ws:
            async def send(action, payload):
                await ws.send(json.dumps({'header': {'action': action, 'task_id': task, 'streaming': 'duplex'},
                                          'payload': payload}, ensure_ascii=False))
            await send('run-task', {'task_group': 'audio', 'task': 'tts', 'function': 'SpeechSynthesizer',
                                   'model': s.voice_model, 'input': {}, 'parameters': {
                                       'text_type': 'PlainText', 'voice': voice, 'format': 'pcm',
                                       'sample_rate': 24000, 'rate': 1.0, 'pitch': 1.0,
                                       'instruction': styles[expression]}})
            chunks = bytearray()
            started = False
            async for item in ws:
                if isinstance(item, bytes):
                    if not started:
                        raise ProviderError('VOICE_PROTOCOL_ERROR')
                    chunks.extend(item)
                    if len(chunks) > 12 * 1024 * 1024:
                        raise ProviderError('VOICE_TOO_LARGE')
                    continue
                event = json.loads(item).get('header', {})
                if event.get('task_id') != task:
                    raise ProviderError('VOICE_PROTOCOL_ERROR')
                if event.get('event') == 'task-started':
                    if started:
                        raise ProviderError('VOICE_PROTOCOL_ERROR')
                    started = True
                    await send('continue-task', {'input': {'text': text}})
                    await send('finish-task', {'input': {}})
                elif event.get('event') == 'task-failed':
                    raise ProviderError('VOICE_UNAVAILABLE')
                elif event.get('event') == 'task-finished':
                    if not chunks or len(chunks) % 2:
                        raise ProviderError('VOICE_EMPTY')
                    return wav(chunks)
            raise ProviderError('VOICE_INCOMPLETE')


def wav(pcm: bytes) -> bytes:
    output = io.BytesIO()
    with wave.open(output, 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(24000)
        f.writeframes(pcm)
    return output.getvalue()
