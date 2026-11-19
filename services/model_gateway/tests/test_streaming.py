import asyncio
import json
import struct

import pytest
from fastapi.testclient import TestClient

from gateway.app import create_app
from gateway.providers import ProviderError, Settings
from gateway.speech_pool import SpeechPool

TOKEN = 'local-test-token-not-real-provider-key'
HEADERS = {'Authorization': 'Bearer '+TOKEN}
PATH = '/v2/conversations/local-xing/stream'


class Chat:
    def __init__(self): self.calls = 0
    async def reply(self, character, history, content):
        self.calls += 1
        if content == 'wait': await asyncio.sleep(10)
        if content == 'fail': raise ProviderError('MODEL_INCOMPLETE')
        yield '完整'
        yield '回复'


class Pool:
    def __init__(self): self.calls = 0; self.fail = False; self.wait = False; self.closed = False
    async def close(self): self.closed = True
    async def stream(self, text, role, expression, metrics):
        assert text == '完整回复'
        self.calls += 1
        metrics.update(reused=self.calls>1,connection_serial=1)
        if self.fail: raise ProviderError('VOICE_UNAVAILABLE')
        yield b'\x00\x01'*1200
        if self.wait: await asyncio.sleep(10)
        yield b'\x02\x00'*1200


def setup(tmp_path):
    chat, pool = Chat(), Pool()
    app = create_app(Settings(mode='mock',token=TOKEN,data_dir=str(tmp_path)),chat,pool)
    return app, chat, pool


def send(ws, rid='request-stream-0001', **kwargs):
    ws.send_json(dict(command='chat.send',request_id=rid,character_id='xing',content='hi',**kwargs))


def receive(ws):
    packet = ws.receive()
    if packet.get('bytes'):
        value = packet['bytes']; size=struct.unpack('!I',value[:4])[0]
        data=json.loads(value[4:4+size]);data['pcm']=value[4+size:];return data
    return json.loads(packet['text'])


def until(ws, event):
    rows=[]
    for _ in range(30):
        row=receive(ws);rows.append(row)
        if row['event']==event:return rows
    raise AssertionError('Missing '+event)


def test_server_orchestrates_text_first_and_same_request_does_not_repeat(tmp_path):
    app,chat,pool=setup(tmp_path)
    with TestClient(app) as client, client.websocket_connect(PATH,headers=HEADERS) as ws:
        assert receive(ws)['event']=='session.ready'
        send(ws)
        rows=until(ws,'audio.completed')
        names=[r['event'] for r in rows]
        assert names.index('message.completed') < names.index('audio.started') < names.index('audio.chunk')
        chunks=[r for r in rows if r['event']=='audio.chunk']
        assert [c['seq'] for c in chunks]==[0,1] and [c['offset'] for c in chunks]==[0,2400]
        assert chat.calls==pool.calls==1
        send(ws)
        assert receive(ws)['event']=='turn.status'
        assert chat.calls==pool.calls==1
        ws.send_json(dict(command='chat.send',request_id='request-stream-0001',character_id='xing',content='different'))
        assert receive(ws)['code']=='REQUEST_ID_CONFLICT'


def test_no_voice_on_disabled_or_incomplete_chat(tmp_path):
    app,chat,pool=setup(tmp_path)
    with TestClient(app) as client, client.websocket_connect(PATH,headers=HEADERS) as ws:
        receive(ws);send(ws,speech={'enabled':False})
        assert until(ws,'message.completed')[-1]['speech_id']==''
        ws.send_json(dict(command='chat.send',request_id='request-stream-0002',character_id='xing',content='fail'))
        assert until(ws,'message.failed')[-1]['code']=='MODEL_INCOMPLETE'
        assert pool.calls==0


def test_empty_audio_is_failure_but_completed_text_survives(tmp_path):
    app,chat,pool=setup(tmp_path)
    async def empty(*args):
        for part in []:
            yield part
    pool.stream=empty
    with TestClient(app) as client, client.websocket_connect(PATH,headers=HEADERS) as ws:
        receive(ws);send(ws)
        assert until(ws,'audio.failed')[-1]['code']=='VOICE_EMPTY'
        row=app.state.streaming.store.get('turns','request-stream-0001')
        assert row['text']=='完整回复' and row['status']=='completed'


def test_bounded_ledger_rejects_without_calling_models(tmp_path):
    app,chat,pool=setup(tmp_path)
    with TestClient(app) as client, client.websocket_connect(PATH,headers=HEADERS) as ws:
        store=app.state.streaming.store
        for i in range(200):
            store.claim(dict(request_id=f'capacity-request-{i:04}',character_id='xing',content='hi'))
            store.finish_turn(f'capacity-request-{i:04}','completed',text='synthetic')
        receive(ws);send(ws)
        assert receive(ws)['code']=='LOCAL_CAPACITY_REACHED'
        assert chat.calls==pool.calls==0


def test_voice_failure_retry_preserves_text_and_deduplicates(tmp_path):
    app,chat,pool=setup(tmp_path);pool.fail=True
    with TestClient(app) as client, client.websocket_connect(PATH,headers=HEADERS) as ws:
        receive(ws);send(ws)
        rows=until(ws,'audio.failed'); assert any(r['event']=='message.completed' for r in rows)
        pool.fail=False
        command=dict(command='speech.retry',request_id='request-stream-0001',speech_id='voice-retry-000001')
        ws.send_json(command);until(ws,'audio.completed')
        ws.send_json(command); replay=until(ws,'audio.completed')
        assert replay[-1]['cached'] and chat.calls==1 and pool.calls==2
        assert app.state.streaming.store.get('turns','request-stream-0001')['status']=='completed'


def test_stop_voice_then_next_reply_has_no_old_packets(tmp_path):
    app,chat,pool=setup(tmp_path);pool.wait=True
    with TestClient(app) as client, client.websocket_connect(PATH,headers=HEADERS) as ws:
        receive(ws);send(ws);until(ws,'audio.chunk')
        ws.send_json(dict(command='speech.cancel',request_id='request-stream-0001'))
        until(ws,'audio.cancelled')
        assert app.state.streaming.store.get('turns','request-stream-0001')['status']=='completed'
        pool.wait=False;send(ws,'request-stream-0002')
        rows=until(ws,'audio.completed')
        assert all(r['request_id']=='request-stream-0002' for r in rows)


def test_disconnect_status_and_restart_never_reissue(tmp_path):
    app,chat,pool=setup(tmp_path);pool.wait=True
    with TestClient(app) as client:
        with client.websocket_connect(PATH,headers=HEADERS) as ws:
            receive(ws);send(ws);until(ws,'audio.chunk')
        with client.websocket_connect(PATH,headers=HEADERS) as ws:
            receive(ws);ws.send_json(dict(command='turn.status',request_id='request-stream-0001'))
            row=receive(ws);assert row['content']=='完整回复' and row['status']=='completed'
        assert chat.calls==pool.calls==1
    app2,chat2,pool2=setup(tmp_path)
    with TestClient(app2) as client, client.websocket_connect(PATH,headers=HEADERS) as ws:
        receive(ws);ws.send_json(dict(command='turn.status',request_id='request-stream-0001'))
        row=receive(ws);assert row['content']=='完整回复' and row['speech_status'] in ('cancelled','failed')
        assert chat2.calls==pool2.calls==0


def test_auth_role_validation_and_cancel_before_completion(tmp_path):
    app,chat,pool=setup(tmp_path)
    with TestClient(app) as client:
        with pytest.raises(Exception):
            with client.websocket_connect(PATH): pass
        with client.websocket_connect(PATH,headers=HEADERS) as ws:
            receive(ws)
            ws.send_json(dict(command='chat.send',request_id='request-stream-0001',character_id='yue',content='hi'))
            assert receive(ws)['code']=='INVALID_REQUEST'
            ws.send_json(dict(command='chat.send',request_id='request-stream-0001',character_id='xing',content='wait'))
            until(ws,'message.started')
            ws.send_json(dict(command='turn.cancel',request_id='request-stream-0001'))
            until(ws,'message.cancelled')
            assert pool.calls==0


@pytest.mark.parametrize('proxy', [None, 'http://127.0.0.1:9999'])
def test_provider_connection_reuse_expiry_and_cancel_discard(proxy):
    class Socket:
        def __init__(self): self.frames=asyncio.Queue(); self.closed=False
        async def close(self): self.closed=True
        async def send(self, raw):
            p=json.loads(raw);rid=p['header']['task_id'];action=p['header']['action']
            if action=='run-task': await self.frames.put(json.dumps({'header':{'task_id':rid,'event':'task-started'}}))
            if action=='finish-task':
                await self.frames.put(b'\x00\x01'*1200)
                await self.frames.put(json.dumps({'header':{'task_id':rid,'event':'task-finished'}}))
        async def recv(self): return await self.frames.get()
    async def scenario():
        sockets=[]
        async def connector(*args,**kwargs):
            assert kwargs['proxy'] == proxy
            sock=Socket();sockets.append(sock);return sock
        pool=SpeechPool(Settings(dashscope_key='fake',voice='fake',voice_proxy=proxy),connector)
        first={};second={}
        _=[x async for x in pool.stream('hi','xing','calm',first)]
        _=[x async for x in pool.stream('hi','xing','calm',second)]
        assert not first['reused'] and second['reused'] and len(sockets)==1
        stream=pool.stream('cancel','xing','calm',{})
        await anext(stream);await stream.aclose()
        assert sockets[0].closed and pool.socket is None
        _=[x async for x in pool.stream('hi','xing','calm',{})]
        assert len(sockets)==2
        pool.last_used-=46
        _=[x async for x in pool.stream('hi','xing','calm',{})]
        assert len(sockets)==3 and sockets[1].closed
        await pool.close()
    asyncio.run(scenario())


def test_deepseek_http_client_reused_and_closed():
    from gateway.providers import Providers
    async def scenario():
        provider = Providers(Settings())
        async with provider.http_client() as first:
            assert not first.is_closed
        async with provider.http_client() as second:
            assert second is first and not first.is_closed
        await provider.close()
        assert first.is_closed
    asyncio.run(scenario())
