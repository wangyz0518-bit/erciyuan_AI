import asyncio
import json
import struct
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from client import Client, decode, load_config, LabError
from store import Store
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed


class FakePlayer:
    instances = []
    def __init__(self, device=None):
        self.first_output = None
        self.finished = threading.Event()
        self.closed = False
        self.data = bytearray()
        self.instances.append(self)
    def feed(self, pcm):
        self.data.extend(pcm)
        self.first_output = time.perf_counter()
    def end(self): self.finished.set()
    def close(self): self.closed = True
    def metrics(self): return {'frames': len(self.data)//2, 'underflows': 0, 'starved_ms': 0}


class ProtocolTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.calls = self.voices = self.connections = 0
        self.fail_voice = self.bad_sequence = self.wrong_text = self.wait_text = self.wait_audio = False
        self.received = asyncio.Event()
        self.release = asyncio.Event()
        self.contexts = []
        FakePlayer.instances = []
        self.server = await serve(self.handler, '127.0.0.1', 0)
        port = self.server.sockets[0].getsockname()[1]
        self.path = Path(self.directory.name)/'history.sqlite'
        self.client = Client(f'http://127.0.0.1:{port}', 'test-development-token-not-a-secret', self.path,
                             player_factory=FakePlayer)

    async def handler(self, ws):
        self.connections += 1
        role = 'yue' if 'local-yue' in ws.request.path else 'xing'
        await ws.send(json.dumps({'event':'session.ready','protocol':2}))
        try:
            async for raw in ws:
                p = json.loads(raw)
                rid = p['request_id']
                sid = p.get('speech_id', 'synthetic-voice-0001')
                async def send(event, **fields):
                    await ws.send(json.dumps(dict(event=event, request_id=rid, character_id=role, **fields)))
                if p['command'] == 'chat.send':
                    self.calls += 1
                    self.contexts.append(p['history'])
                    self.received.set()
                    if self.wait_text:
                        await self.release.wait()
                    await send('message.delta', delta='合成测试回复')
                    await send('message.completed', content='错误' if self.wrong_text else '合成测试回复', speech_id=sid)
                if p['command'] in ('chat.send','speech.retry'):
                    self.voices += 1
                    if self.fail_voice:
                        await send('audio.failed', speech_id=sid, code='VOICE_UNAVAILABLE')
                        continue
                    await send('audio.started', speech_id=sid, format='pcm_s16le', sample_rate=24000, channels=1, reused=self.voices>1)
                    pcm = b'\x00\x08'*2400
                    header = json.dumps(dict(event='audio.chunk', request_id=rid, character_id=role,
                                             speech_id=sid, seq=1 if self.bad_sequence else 0, offset=0)).encode()
                    await ws.send(struct.pack('!I', len(header))+header+pcm)
                    if self.wait_audio:
                        self.received.set()
                        await self.release.wait()
                    await send('audio.completed', speech_id=sid, bytes=len(pcm), chunks=1)
        except ConnectionClosed:
            pass

    async def asyncTearDown(self):
        await self.client.close()
        self.release.set()
        self.server.close()
        await self.server.wait_closed()
        self.directory.cleanup()

    async def test_real_wire_pcm_order_reuse_and_role_history(self):
        await self.client.run('第一句')
        self.assertEqual(self.client.store.last('xing')['text_state'], 'complete')
        self.assertIn('output_ms', self.client.metrics)
        await self.client.run('第二句')
        self.assertEqual(self.connections, 1)
        self.assertEqual(len(self.contexts[-1]), 2)
        await self.client.select('yue')
        await self.client.run('独立角色')
        self.assertEqual(self.contexts[-1], [])
        self.assertEqual(self.connections, 2)
        self.assertEqual(len(self.client.store.rows('xing')), 2)

    async def test_voice_retry_keeps_text_and_never_calls_chat(self):
        self.fail_voice = True
        await self.client.run('声音失败')
        self.assertEqual(self.client.store.last('xing')['text_state'], 'complete')
        self.fail_voice = False
        await self.client.run(voice_retry=True)
        self.assertEqual((self.calls, self.voices), (1, 2))
        self.assertEqual(len(self.client.store.rows('xing')), 1)
        self.assertEqual(self.client.store.last('xing')['audio_state'], 'complete')
        self.assertNotIn('text_ms', self.client.metrics)

    async def test_complete_save_failure_never_opens_audio(self):
        self.client.store.db.execute("CREATE TRIGGER reject_complete BEFORE UPDATE ON turns WHEN NEW.text_state='complete' BEGIN SELECT RAISE(ABORT,'test'); END")
        await self.client.run('写入失败')
        self.assertEqual(FakePlayer.instances, [])
        self.assertEqual(self.client.last_error, 'LOCAL_SAVE_FAILED')
        self.assertEqual(self.client.store.last('xing')['text_state'], 'failed')

    async def test_malformed_pcm_preserves_text_but_cannot_play(self):
        self.bad_sequence = True
        await self.client.run('错误序号')
        self.assertEqual(self.client.last_error, 'AUDIO_SEQUENCE_ERROR')
        self.assertEqual(len(FakePlayer.instances[0].data), 0)
        self.assertTrue(FakePlayer.instances[0].closed)
        self.assertEqual(self.client.store.last('xing')['text_state'], 'complete')

    async def test_mismatched_text_is_not_spoken_and_retry_reuses_local_row(self):
        self.wrong_text = True
        await self.client.run('原提问')
        first = self.client.store.last('xing')
        self.assertEqual(FakePlayer.instances, [])
        self.wrong_text = False
        await self.client.run(text_retry=True)
        second = self.client.store.last('xing')
        self.assertEqual(first['id'], second['id'])
        self.assertNotEqual(first['request_id'], second['request_id'])
        self.assertEqual(self.contexts[-1], [])
        self.assertEqual(second['text_state'], 'complete')

    async def test_cancel_text_no_automatic_resubmit(self):
        self.wait_text = True
        job = asyncio.create_task(self.client.run('取消等待'))
        await asyncio.wait_for(self.received.wait(), 2)
        await self.client.stop()
        await job
        self.assertEqual(self.client.store.last('xing')['text_state'], 'cancelled')
        self.assertEqual(self.calls, 1)
        self.assertFalse(self.client.busy)
        self.assertEqual(FakePlayer.instances, [])

    async def test_cancel_audio_aborts_and_retains_completed_text(self):
        self.wait_audio = True
        job = asyncio.create_task(self.client.run('停止声音'))
        for _ in range(100):
            if FakePlayer.instances and FakePlayer.instances[0].data:
                break
            await asyncio.sleep(.01)
        await self.client.stop()
        await job
        self.assertTrue(FakePlayer.instances[0].closed)
        row = self.client.store.last('xing')
        self.assertEqual((row['text_state'], row['audio_state']), ('complete', 'cancelled'))


class StoreTests(unittest.TestCase):
    def test_reopen_and_interrupted_records_not_used_as_context(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'test.sqlite'
            store = Store(path)
            a = store.begin('request-01', 'xing', '完成的提问')
            store.text(a, '完成的回答', 'complete')
            store.begin('request-02', 'xing', '未完成的提问')
            store.close()
            store = Store(path)
            self.assertEqual(store.last('xing')['text_state'], 'interrupted')
            self.assertEqual(len(store.history('xing')), 2)
            self.assertEqual(store.history('yue'), [])
            store.close()

    def test_rejects_insecure_remote_config_and_malformed_frame(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'config.json'
            path.write_text(json.dumps({'MODEL_GATEWAY_URL':'http://example.com','MODEL_GATEWAY_TOKEN':'x'*32}))
            with self.assertRaises(LabError): load_config(path)
        for raw in (b'\x00', b'\x00\x00\x10\x01payload', '[]'):
            with self.assertRaises((LabError, ValueError)): decode(raw)


if __name__ == '__main__':
    unittest.main()
