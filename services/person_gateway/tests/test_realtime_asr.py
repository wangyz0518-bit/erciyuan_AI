import asyncio
import json

import pytest

from realtime_asr import QwenASR, ProviderError
from voice_input import InputSettings as Settings


class Peer:
    def __init__(self, config_error=False):
        self.events = asyncio.Queue()
        self.sent = []
        self.closed = False
        self.config_error = config_error

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        self.closed = True

    async def send(self, raw):
        packet = json.loads(raw)
        self.sent.append(packet)
        if packet['type'] == 'session.update':
            await self.events.put({'type': 'error' if self.config_error else 'session.updated'})
        if packet['type'] == 'input_audio_buffer.commit':
            await self.events.put({'type': 'conversation.item.input_audio_transcription.text', 'text': '今天', 'stash': '晴天'})
            await self.events.put({'type': 'conversation.item.input_audio_transcription.completed', 'transcript': '今天是晴天。'})

    async def recv(self):
        return json.dumps(await self.events.get())


async def chunks(*items):
    for item in items:
        yield item


def test_manual_commit_returns_final_not_partial_and_closes():
    async def run():
        peer, partials = Peer(), []
        async def partial(value): partials.append(value)
        asr = QwenASR(Settings(mode='live', dashscope_key='test-key'), lambda *a, **kw: peer)
        result = await asr.transcribe(chunks(b'\0\0' * 3200), partial)
        assert result == '今天是晴天。' and partials == ['今天晴天']
        assert [p['type'] for p in peer.sent] == ['session.update', 'input_audio_buffer.append', 'input_audio_buffer.commit']
        assert peer.sent[0]['session']['turn_detection'] is None
        assert peer.closed
    asyncio.run(run())


@pytest.mark.parametrize('pcm,code', [(b'\0', 'INVALID_INPUT_AUDIO'), (b'\0\0' * 10, 'INPUT_AUDIO_TOO_SHORT')])
def test_invalid_capture_fails_without_waiting_for_silent_server(pcm, code):
    async def run():
        peer = Peer()
        asr = QwenASR(Settings(mode='live', dashscope_key='test-key'), lambda *a, **kw: peer)
        with pytest.raises(ProviderError, match=code):
            await asyncio.wait_for(asr.transcribe(chunks(pcm), None), 1)
        assert peer.closed and not any(p['type'] == 'input_audio_buffer.commit' for p in peer.sent)
    asyncio.run(run())


def test_cancel_capture_never_commits_and_closes_sender():
    async def run():
        peer, released = Peer(), asyncio.Event()
        async def capture():
            try:
                yield b'\0\0' * 3200
                await asyncio.Event().wait()
            finally:
                released.set()
        asr = QwenASR(Settings(mode='live', dashscope_key='test-key'), lambda *a, **kw: peer)
        task = asyncio.create_task(asr.transcribe(capture(), None))
        while not any(p['type'] == 'input_audio_buffer.append' for p in peer.sent):
            await asyncio.sleep(0)
        task.cancel()
        with pytest.raises(asyncio.CancelledError): await task
        assert released.is_set() and peer.closed
        assert not any(p['type'] == 'input_audio_buffer.commit' for p in peer.sent)
    asyncio.run(run())


def test_model_reject_is_redacted_and_mock_never_calls_supplier():
    async def run():
        peer = Peer(config_error=True)
        asr = QwenASR(Settings(mode='live', dashscope_key='test-key'), lambda *a, **kw: peer)
        with pytest.raises(ProviderError, match='ASR_CONFIG_REJECTED'):
            await asr.transcribe(chunks(b'\0\0' * 3200), None)
        assert peer.closed
        def forbidden(*a, **kw): raise AssertionError('Mock attempted network')
        with pytest.raises(ProviderError, match='ASR_LIVE_REQUIRED'):
            await QwenASR(Settings(mode='mock'), forbidden).transcribe(chunks(), None)
    asyncio.run(run())
