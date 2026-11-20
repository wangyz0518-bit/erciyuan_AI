"""Bounded Qwen realtime ASR. Manual endpointing has exactly one owner.

PCM is streamed while the user speaks; only the final transcript may be sent
to the chat model. Closing/cancelling never commits an unfinished recording.
"""
import asyncio
import base64
import json
import logging
import re
import uuid
from urllib.parse import quote

from websockets.asyncio.client import connect

from .providers import ProviderError

logger = logging.getLogger(__name__)


class QwenASR:
    def __init__(self, settings, connector=connect):
        self.settings, self.connector = settings, connector

    async def transcribe(self, chunks, partial):
        s = self.settings
        if s.mode != 'live':
            # Mock input must never pretend that we recognized real speech.
            raise ProviderError('ASR_LIVE_REQUIRED')
        if not s.dashscope_key:
            raise ProviderError('ASR_NOT_CONFIGURED')
        if s.workspace and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]{0,127}', s.workspace):
            raise ProviderError('ASR_NOT_CONFIGURED')
        host = f'{s.workspace}.cn-beijing.maas.aliyuncs.com' if s.workspace else 'dashscope.aliyuncs.com'
        url = f'wss://{host}/api-ws/v1/realtime?model={quote(s.asr_model, safe="")}'
        sender = None
        phase = 'connect'
        try:
            async with asyncio.timeout(65):
                async with self.connector(url, additional_headers={'Authorization': 'Bearer '+s.dashscope_key},
                                          proxy=s.voice_proxy, open_timeout=10, close_timeout=1,
                                          max_size=1024*1024) as socket:
                    phase = 'configure'
                    async def send(kind, **fields):
                        await socket.send(json.dumps(dict(type=kind, event_id=uuid.uuid4().hex, **fields)))

                    await send('session.update', session={
                        'input_audio_format': 'pcm', 'sample_rate': 16000,
                        'input_audio_transcription': {'language': 'zh'}, 'turn_detection': None})
                    async with asyncio.timeout(10):
                        while True:
                            event = json.loads(await socket.recv())
                            if event.get('type') == 'session.updated':
                                break
                            if event.get('type') == 'error':
                                raise ProviderError('ASR_CONFIG_REJECTED')

                    async def feed():
                        total = 0
                        async for chunk in chunks:
                            if not chunk or len(chunk) % 2 or len(chunk) > 6400:
                                raise ProviderError('INVALID_INPUT_AUDIO')
                            total += len(chunk)
                            if total > 16000*2*30:
                                raise ProviderError('INPUT_AUDIO_TOO_LONG')
                            await send('input_audio_buffer.append', audio=base64.b64encode(chunk).decode())
                        if total < 16000*2//5:
                            raise ProviderError('INPUT_AUDIO_TOO_SHORT')
                        await send('input_audio_buffer.commit')

                    sender = asyncio.create_task(feed())
                    phase = 'transcribe'
                    # Observe a failed producer even when the remote peer stays silent.
                    while True:
                        receive = asyncio.create_task(socket.recv())
                        try:
                            # Manual ASR can remain silent throughout a 30 s
                            # recording. Start the final-result deadline only
                            # after commit; the outer bound covers capture.
                            if not sender.done():
                                await asyncio.wait({receive, sender}, return_when=asyncio.FIRST_COMPLETED)
                            if sender.done():
                                sender.result()
                            raw = await asyncio.wait_for(receive, 15)
                        finally:
                            if not receive.done():
                                receive.cancel()
                            await asyncio.gather(receive, return_exceptions=True)
                        event = json.loads(raw)
                        kind = event.get('type', '')
                        if kind == 'conversation.item.input_audio_transcription.text':
                            preview = event.get('text', '') + event.get('stash', '')
                            if len(preview) > 2000:
                                raise ProviderError('INPUT_TEXT_TOO_LONG')
                            await partial(preview)
                        elif kind == 'conversation.item.input_audio_transcription.completed':
                            if not sender.done():
                                raise ProviderError('ASR_UNEXPECTED_FINAL')
                            sender.result()
                            text = event.get('transcript', '').strip()
                            if not text:
                                raise ProviderError('ASR_EMPTY')
                            if len(text) > 2000:
                                raise ProviderError('INPUT_TEXT_TOO_LONG')
                            return text
                        elif kind in ('error', 'conversation.item.input_audio_transcription.failed', 'session.finished'):
                            raise ProviderError('ASR_FAILED')
        except ProviderError:
            raise
        except TimeoutError:
            raise ProviderError('ASR_TIMEOUT') from None
        except Exception as exc:
            # Diagnostic type/status only: exception strings may contain URLs,
            # provider content or headers and must never be logged.
            http_status = getattr(getattr(exc, 'response', None), 'status_code', None)
            close_code = getattr(getattr(exc, 'rcvd', None), 'code', None)
            logger.warning('ASR transport failed: type=%s phase=%s http=%s close=%s',
                           type(exc).__name__, phase, http_status, close_code)
            raise ProviderError('ASR_UNAVAILABLE') from None
        finally:
            if sender is not None:
                sender.cancel()
                await asyncio.gather(sender, return_exceptions=True)
