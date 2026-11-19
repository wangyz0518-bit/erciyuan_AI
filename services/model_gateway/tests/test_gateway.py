import asyncio
import json

import httpx
from fastapi.testclient import TestClient

from gateway.app import Ledger, create_app
from gateway.providers import ProviderError, Providers, Settings, wav

TOKEN = 'test-token-only-no-real-provider-key'
HEADERS = {'Authorization': 'Bearer ' + TOKEN}


class FakeProviders:
    def __init__(self):
        self.chats = 0
        self.voices = 0
        self.spoken = []
        self.voice_fail = False

    async def reply(self, character, history, content):
        self.chats += 1
        if content == 'wait':
            await asyncio.sleep(5)
        if content == 'fail':
            raise ProviderError('MODEL_TIMEOUT')
        yield '完整'
        yield '回答'

    async def speech(self, text, character, expression):
        self.voices += 1
        self.spoken.append(text)
        if self.voice_fail:
            raise ProviderError('VOICE_UNAVAILABLE')
        return wav(bytes(48000))


def payload(rid='chat-request-000001', **extra):
    return {'request_id': rid, 'character_id': 'xing', 'content': '你好', **extra}


def setup(tmp_path, providers=None):
    providers = providers or FakeProviders()
    app = create_app(Settings(mode='mock', token=TOKEN, data_dir=str(tmp_path)), providers)
    return app, providers


def test_stream_replay_conflict_and_no_duplicate_model_call(tmp_path):
    app, p = setup(tmp_path)
    with TestClient(app) as client:
        path = '/v1/conversations/local-xing/messages'
        first = client.post(path, json=payload(), headers=HEADERS)
        assert first.status_code == 200 and 'message.completed' in first.text
        assert '完整回答' in first.text
        replay = client.post(path, json=payload(), headers=HEADERS)
        assert '完整回答' in replay.text and p.chats == 1
        assert client.post(path, json=payload(content='changed'), headers=HEADERS).status_code == 409
        assert p.chats == 1


def test_voice_requires_completed_same_role_and_retries_independently(tmp_path):
    app, p = setup(tmp_path)
    with TestClient(app) as client:
        body = {'request_id': 'speech-request-0001', 'reply_request_id': 'chat-request-000001', 'character_id': 'xing'}
        assert client.post('/v1/audio/speech', json=body, headers=HEADERS).status_code == 409
        client.post('/v1/conversations/local-xing/messages', json=payload(), headers=HEADERS)
        assert client.post('/v1/audio/speech', json={**body, 'character_id': 'yue'}, headers=HEADERS).status_code == 409
        p.voice_fail = True
        assert client.post('/v1/audio/speech', json=body, headers=HEADERS).status_code == 502
        assert app.state.ledger.get('chat-request-000001')['text'] == '完整回答'
        p.voice_fail = False
        # Same ID replays failure, never silently bills another request.
        assert client.post('/v1/audio/speech', json=body, headers=HEADERS).status_code == 502
        assert p.voices == 1
        body['request_id'] = 'speech-request-0002'
        audio = client.post('/v1/audio/speech', json=body, headers=HEADERS)
        assert audio.status_code == 200 and audio.content.startswith(b'RIFF')
        assert client.post('/v1/audio/speech', json=body, headers=HEADERS).content == audio.content
        assert p.chats == 1 and p.voices == 2 and p.spoken == ['完整回答', '完整回答']


def test_auth_validation_and_asr_stub_do_not_call_providers(tmp_path):
    app, p = setup(tmp_path)
    with TestClient(app) as client:
        assert client.post('/v1/conversations/local-xing/messages', json=payload()).status_code == 401
        invalid = client.post('/v1/conversations/local-yue/messages', json=payload(), headers=HEADERS)
        assert invalid.status_code == 422
        invalid = client.post('/v1/conversations/local-xing/messages', json=payload(content='x'*2001), headers=HEADERS)
        assert invalid.status_code == 422 and 'x'*100 not in invalid.text
        stub = client.post('/v1/audio/transcriptions', content=b'not audio', headers=HEADERS)
        assert stub.status_code == 501 and stub.json()['error']['code'] == 'ASR_NOT_IMPLEMENTED'
        assert p.chats == p.voices == 0


def test_model_error_is_terminal_and_retry_uses_new_id(tmp_path):
    app, p = setup(tmp_path)
    with TestClient(app) as client:
        path = '/v1/conversations/local-xing/messages'
        response = client.post(path, json=payload(content='fail'), headers=HEADERS)
        assert 'MODEL_TIMEOUT' in response.text and 'message.completed' not in response.text
        client.post(path, json=payload(content='fail'), headers=HEADERS)
        assert p.chats == 1
        assert 'message.completed' in client.post(path, json=payload('chat-request-000002'), headers=HEADERS).text
        assert p.chats == 2


def test_cancel_running_request_and_late_results(tmp_path):
    async def scenario():
        app, p = setup(tmp_path)
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://test', headers=HEADERS) as client:
            task = asyncio.create_task(client.post('/v1/conversations/local-xing/messages', json=payload(content='wait')))
            while not p.chats:
                await asyncio.sleep(.01)
            response = await client.post('/v1/requests/chat-request-000001/cancel')
            assert response.json()['status'] == 'cancelled'
            result = await task
            assert 'message.completed' not in result.text
            assert app.state.ledger.get('chat-request-000001')['status'] == 'cancelled'
            assert p.voices == 0
        app.state.ledger.db.close()
    asyncio.run(scenario())


def test_restart_replay_and_ambiguous_request_not_reissued(tmp_path):
    app, p = setup(tmp_path)
    with TestClient(app) as client:
        client.post('/v1/conversations/local-xing/messages', json=payload(), headers=HEADERS)
        app.state.ledger.claim(payload('chat-request-pending'), 'chat')
    app2, p2 = setup(tmp_path)
    with TestClient(app2) as client:
        assert '完整回答' in client.post('/v1/conversations/local-xing/messages', json=payload(), headers=HEADERS).text
        assert app2.state.ledger.get('chat-request-pending')['code'] == 'SERVER_RESTARTED'
        assert p2.chats == 0


def test_deepseek_wire_filters_reasoning_and_handles_stop(monkeypatch):
    actual_client = httpx.AsyncClient
    def handler(request):
        body = json.loads(request.content)
        assert body['stream'] is True and body['messages'][0]['role'] == 'system'
        packets = [ {'choices': [{'delta': {'reasoning_content': 'never speak this'}}]},
                    {'choices': [{'delta': {'content': '你好'}}]},
                    {'choices': [{'delta': {}, 'finish_reason': 'stop'}]}]
        stream = ''.join('data: '+json.dumps(p)+'\n\n' for p in packets)+'data: [DONE]\n\n'
        return httpx.Response(200, text=stream)
    monkeypatch.setattr('gateway.providers.httpx.AsyncClient', lambda **kwargs: actual_client(transport=httpx.MockTransport(handler)))
    async def scenario():
        provider = Providers(Settings(deepseek_key='fake'))
        result = ''.join([s async for s in provider.reply('xing', [], 'hi')])
        assert result == '你好'
    asyncio.run(scenario())


def test_deepseek_truncated_stream_is_not_completed(monkeypatch):
    actual_client = httpx.AsyncClient
    monkeypatch.setattr('gateway.providers.httpx.AsyncClient', lambda **kwargs: actual_client(
        transport=httpx.MockTransport(lambda r: httpx.Response(200, text='data: {"choices":[{"delta":{"content":"half"}}]}\n\n'))))
    async def scenario():
        try:
            _ = [s async for s in Providers(Settings(deepseek_key='fake')).reply('xing', [], 'hi')]
        except ProviderError as error:
            assert error.code == 'MODEL_INCOMPLETE'
        else:
            assert False, 'truncated stream must fail'
    asyncio.run(scenario())


def test_cosyvoice_wire_waits_for_started_and_wraps_pcm(monkeypatch):
    class Socket:
        def __init__(self):
            self.sent = []
        async def __aenter__(self): return self
        async def __aexit__(self, *args): pass
        async def send(self, value): self.sent.append(json.loads(value))
        async def __aiter__(self):
            task = self.sent[0]['header']['task_id']
            assert len(self.sent) == 1
            yield json.dumps({'header': {'task_id': task, 'event': 'task-started'}})
            assert self.sent[1]['payload']['input']['text'] == '完整回答'
            assert self.sent[2]['header']['action'] == 'finish-task'
            yield bytes(48000)
            yield json.dumps({'header': {'task_id': task, 'event': 'task-finished'}})
    socket = Socket()
    monkeypatch.setattr('gateway.providers.connect', lambda *args, **kwargs: socket)
    result = asyncio.run(Providers(Settings(dashscope_key='fake', voice='fake')).speech('完整回答', 'xing', 'calm'))
    assert result.startswith(b'RIFF') and len(result) == 48044
    assert socket.sent[0]['payload']['model'] == 'cosyvoice-v3.5-flash'
