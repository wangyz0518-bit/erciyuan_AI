import asyncio
import io
import json
import sqlite3
import struct
import wave

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from gateway.app import create_app
from gateway.conversation_store import ConversationStore
from gateway.providers import Settings, ProviderError

TOKEN = 'local-development-only-token-0001'
RID = 'conversation-turn-0001'
HEADERS = {'Authorization': 'Bearer '+TOKEN}


class Chat:
    def __init__(self):
        self.calls = []

    async def reply(self, role, history, content):
        self.calls.append((role, history, content))
        if content == 'wait':
            await asyncio.sleep(30)
        yield '你好，'
        if content == 'fail':
            raise ProviderError('MODEL_INCOMPLETE')
        yield '我们继续聊。'


class Pool:
    def __init__(self):
        self.cancelled = False
        self.wait = False

    async def stream(self, *args):
        try:
            yield b'\x01\x00'*1200
            if self.wait:
                await asyncio.sleep(30)
            yield b'\x02\x00'*1200
        finally:
            self.cancelled = True

    async def close(self):
        pass


class ASR:
    def __init__(self):
        self.cancelled = False
        self.received = b''

    async def transcribe(self, chunks, partial):
        try:
            async for chunk in chunks:
                self.received += chunk
                await partial('临时草稿')
            return '识别出的最终文字'
        finally:
            self.cancelled = True


def setup(tmp_path):
    chat, pool, asr = Chat(), Pool(), ASR()
    app = create_app(Settings(mode='mock', token=TOKEN, data_dir=str(tmp_path)), chat, pool, asr=asr)
    return app, chat, pool, asr


def receive(ws):
    packet = ws.receive()
    if packet.get('bytes'):
        raw = packet['bytes']
        size = struct.unpack('!I', raw[:4])[0]
        return json.loads(raw[4:4+size]) | {'pcm': raw[4+size:]}
    return json.loads(packet['text'])


def until(ws, event):
    rows = []
    for _ in range(100):
        row = receive(ws)
        rows.append(row)
        if row['event'] == event:
            return rows
    raise AssertionError(event)


def hello(ws):
    ws.send_json({'command':'session.start', 'token':TOKEN})
    return receive(ws)


def text(ws, content='hi', rid=RID, **fields):
    ws.send_json(dict(command='chat.send', request_id=rid, text=content, **fields))


def pcm(ws, rid=RID, seq=0):
    header = json.dumps(dict(input_id=rid, seq=seq)).encode()
    ws.send_bytes(struct.pack('!I', len(header))+header+b'\x01\x00'*3200)


def test_auth_origin_and_single_session(tmp_path):
    app, *_ = setup(tmp_path)
    with TestClient(app) as client:
        with pytest.raises(WebSocketDisconnect):
            with client.websocket_connect('/v3/conversations/xing/stream', headers={'origin':'https://evil.example'}):
                pass
        with client.websocket_connect('/v3/conversations/xing/stream') as ws:
            ws.send_json({'command':'session.start','token':'wrong'})
            assert receive(ws)['code'] == 'UNAUTHORIZED'
        with client.websocket_connect('/v3/conversations/xing/stream') as ws:
            assert hello(ws)['protocol'] == 3
            with client.websocket_connect('/v3/conversations/yue/stream') as second:
                assert hello(second)['code'] == 'SESSION_BUSY'
        assert client.get('/v3/conversations/xing').status_code == 401


@pytest.mark.parametrize('role', ['xing', 'sprout'])
def test_text_saved_before_audio_replay_no_charge_and_playback_ack(tmp_path, role):
    app, chat, _, _ = setup(tmp_path)
    with TestClient(app) as client, client.websocket_connect(f'/v3/conversations/{role}/stream') as ws:
        assert hello(ws)['character_id'] == role
        binding = client.get(f'/v1/characters/{role}/voice-binding', headers=HEADERS)
        assert binding.json()['character_id'] == role
        text(ws)
        rows = until(ws, 'audio.completed')
        names = [r['event'] for r in rows]
        assert names.index('reply.saved') < names.index('audio.started')
        assert app.state.conversations.store.get(RID)['audio_state'] == 'awaiting_playback'
        ws.send_json(dict(command='playback.progress',reply_id=RID,frames=2400,complete=True))
        until(ws, 'turn.completed')
        text(ws)
        assert receive(ws)['event'] == 'turn.status'
        assert len(chat.calls) == 1
        assert chat.calls[0][0] == role
        assert client.get(f'/v3/conversations/{role}', headers=HEADERS).status_code == 200
        assert app.state.conversations.store.history('yue') == []
        text(ws, speak=False)
        assert receive(ws)['code'] == 'REQUEST_ID_CONFLICT'
        text(ws, 'changed')
        assert receive(ws)['code'] == 'REQUEST_ID_CONFLICT'
        assert app.state.conversations.store.get(RID)['audio_state'] == 'played'


def test_interrupt_synthesis_then_next_turn_and_stale_cancel(tmp_path):
    app, chat, pool, _ = setup(tmp_path)
    pool.wait = True
    with TestClient(app) as client, client.websocket_connect('/v3/conversations/xing/stream') as ws:
        hello(ws); text(ws)
        until(ws, 'audio.chunk')
        ws.send_json(dict(command='turn.interrupt',reply_id=RID))
        assert until(ws,'interrupt.accepted')[-1]['stale'] is False
        assert pool.cancelled
        text(ws, 'wait', rid='conversation-turn-0002')
        until(ws,'turn.saved')
        ws.send_json(dict(command='turn.interrupt',reply_id=RID))
        assert until(ws,'interrupt.accepted')[-1]['stale'] is True
        ws.send_json(dict(command='turn.interrupt',reply_id='conversation-turn-0002'))
        until(ws,'interrupt.accepted')
        assert app.state.conversations.store.get('conversation-turn-0002')['state']=='interrupted'


def test_push_to_talk_final_only_and_recording_replay(tmp_path):
    app, chat, _, _ = setup(tmp_path)
    with TestClient(app) as client, client.websocket_connect('/v3/conversations/xing/stream') as ws:
        hello(ws)
        ws.send_json(dict(command='input.start',input_id=RID,kind='hold'))
        until(ws,'input.ready'); pcm(ws)
        until(ws,'transcript.partial')
        assert not chat.calls
        ws.send_json(dict(command='input.commit',input_id=RID))
        until(ws,'audio.completed')
        assert chat.calls[0][2] == '识别出的最终文字'
        result = client.get('/v3/recordings/'+RID, headers=HEADERS)
        assert result.status_code == 200
        with wave.open(io.BytesIO(result.content)) as audio:
            assert audio.getframerate()==16000 and audio.getnframes()==3200


def test_abort_recording_never_sends_and_can_start_another(tmp_path):
    app, chat, _, asr = setup(tmp_path)
    with TestClient(app) as client, client.websocket_connect('/v3/conversations/xing/stream') as ws:
        hello(ws)
        ws.send_json(dict(command='input.start',input_id=RID,kind='hold'))
        until(ws,'input.ready'); pcm(ws); until(ws,'transcript.partial')
        ws.send_json(dict(command='input.abort',input_id=RID))
        until(ws,'input.aborted')
        assert asr.cancelled and not chat.calls
        assert app.state.conversations.store.get(RID) is None
        ws.send_json(dict(command='input.start',input_id='next-input-00000001',kind='call'))
        until(ws,'input.ready')


def test_sequence_error_aborts_input_and_call_does_not_keep_recording(tmp_path):
    app, chat, _, _ = setup(tmp_path)
    with TestClient(app) as client, client.websocket_connect('/v3/conversations/xing/stream') as ws:
        hello(ws)
        ws.send_json(dict(command='input.start',input_id=RID,kind='call'))
        until(ws,'input.ready'); pcm(ws,seq=1)
        assert receive(ws)['code']=='INPUT_SEQUENCE_ERROR'
        assert not chat.calls
        second='next-input-00000002'
        ws.send_json(dict(command='input.start',input_id=second,kind='call'))
        until(ws,'input.ready'); pcm(ws,rid=second)
        ws.send_json(dict(command='input.commit',input_id=second))
        until(ws,'audio.completed')
        assert app.state.conversations.store.get(second)['recording'] is None
        assert client.get('/v3/recordings/'+second,headers=HEADERS).status_code==404


def test_failed_model_not_spoken_and_progress_cannot_exceed_audio(tmp_path):
    app, _, _, _ = setup(tmp_path)
    with TestClient(app) as client, client.websocket_connect('/v3/conversations/xing/stream') as ws:
        hello(ws); text(ws,'fail')
        rows = until(ws,'turn.failed')
        assert not any(r['event']=='audio.started' for r in rows)
        text(ws,rid='next-turn-000000001')
        until(ws,'audio.completed')
        ws.send_json(dict(command='playback.progress',reply_id='next-turn-000000001',frames=9999,complete=True))
        assert receive(ws)['code']=='INVALID_PLAYBACK_PROGRESS'


def test_restart_role_isolation_and_unheard_call_context(tmp_path):
    store = ConversationStore(tmp_path)
    store.begin(RID,'xing','call','我的问题')
    store.update(RID,reply='还没有播放的秘密内容',state='complete',audio_state='awaiting_playback',total_frames=100)
    store.close()
    store = ConversationStore(tmp_path)
    assert store.get(RID)['audio_state']=='interrupted'
    assert store.rows('yue')==[]
    assert '秘密' not in str(store.history('xing'))
    assert '我的问题' in str(store.history('xing'))
    store.close()


@pytest.mark.parametrize('query', ['rows', 'history'])
def test_history_queries_do_not_return_recording_bytes_from_sqlite(tmp_path, query):
    store = ConversationStore(tmp_path)
    try:
        reader = store.scoped('reader')
        turns = [('one', None), ('two', b''), ('three', b'\x00\x00')]
        expected_context = []
        for turn_id, recording in turns:
            reader.begin(turn_id, 'xing', 'hold', turn_id, recording)
            reader.update(turn_id, state='complete', reply='received')
            expected_context.extend([
                {'role': 'user', 'content': turn_id},
                {'role': 'assistant', 'content': 'received'},
            ])
        store.scoped('author').begin('one', 'xing', 'hold', 'other account')
        reader.begin('four', 'yue', 'text', 'other character')
        expected_rows = [reader.public(reader.get(turn_id)) for turn_id, _ in turns]

        def metadata_row(cursor, values):
            assert not any(isinstance(value, bytes) for value in values)
            return sqlite3.Row(cursor, values)

        store.db.row_factory = metadata_row
        if query == 'rows':
            rows = reader.rows('xing')
            assert rows == expected_rows
            assert all(type(row['has_recording']) is bool for row in rows)
            assert [row['has_recording'] for row in rows] == [False, False, True]
        else:
            assert reader.history('xing') == expected_context
    finally:
        store.close()


def test_history_window_counts_running_turns_before_building_context(tmp_path):
    store = ConversationStore(tmp_path)
    try:
        for index in range(101):
            store.begin(str(index), 'xing', 'text', f'prompt {index}')
        for index in (0, 1, 100):
            store.update(str(index), state='complete', reply=f'reply {index}')
        assert [row['id'] for row in store.rows('xing')] == [str(i) for i in range(1, 101)]
        assert [msg['content'] for msg in store.history('xing')] == [
            'prompt 1', 'reply 1', 'prompt 100', 'reply 100',
        ]
    finally:
        store.close()


def test_late_input_abort_cancels_only_its_reply(tmp_path):
    app, chat, _, _ = setup(tmp_path)
    with TestClient(app) as client, client.websocket_connect('/v3/conversations/xing/stream') as ws:
        hello(ws)
        ws.send_json(dict(command='input.start', input_id=RID, kind='hold'))
        until(ws, 'input.ready'); pcm(ws)
        ws.send_json(dict(command='input.commit', input_id=RID))
        until(ws, 'audio.completed')
        ws.send_json(dict(command='input.abort', input_id=RID))
        until(ws, 'input.aborted')
        assert app.state.conversations.store.get(RID)['audio_state'] == 'interrupted'
        text(ws, 'wait', rid='next-turn-000000003')
        until(ws, 'turn.saved')
        ws.send_json(dict(command='input.abort', input_id=RID))
        until(ws, 'input.aborted')
        assert app.state.conversations.store.get('next-turn-000000003')['state'] == 'running'
        ws.send_json(dict(command='session.ping'))
        until(ws, 'session.pong')


def test_abort_during_final_delivery_does_not_start_model(tmp_path):
    from gateway.conversations import Session
    async def run():
        app, chat, _, _ = setup(tmp_path)
        session = Session(app.state.conversations, None, 'xing')
        reached = asyncio.Event()
        async def emit(event, **fields):
            if event == 'transcript.final':
                reached.set()
                await asyncio.Event().wait()
        session.emit = emit
        await session.command(dict(command='input.start', input_id=RID, kind='call'))
        session.input['queue'].put_nowait(b'\0\0' * 3200)
        await session.command(dict(command='input.commit', input_id=RID))
        await asyncio.wait_for(reached.wait(), 1)
        await session.command(dict(command='input.abort', input_id=RID))
        assert not chat.calls and session.output is None
        assert app.state.conversations.store.get(RID) is None
        await session.close()
        app.state.conversations.store.close()
    asyncio.run(run())


def test_slow_asr_connection_buffers_normal_sized_capture(tmp_path):
    class ConnectingASR(ASR):
        async def transcribe(self, chunks, partial):
            await asyncio.sleep(.3)
            return await super().transcribe(chunks, partial)
    app, chat, _, _ = setup(tmp_path)
    asr = ConnectingASR()
    app.state.conversations.asr = asr
    with TestClient(app) as client, client.websocket_connect('/v3/conversations/xing/stream') as ws:
        hello(ws)
        ws.send_json(dict(command='input.start',input_id=RID,kind='call'))
        until(ws,'input.ready')
        for seq in range(60):
            head=json.dumps(dict(input_id=RID,seq=seq)).encode()
            ws.send_bytes(struct.pack('!I',len(head))+head+b'\x01\x00'*512)
        ws.send_json(dict(command='input.commit',input_id=RID))
        until(ws,'audio.completed')
        assert len(asr.received)==60*1024 and len(chat.calls)==1

def test_next_call_can_start_while_previous_saved_event_is_in_flight(tmp_path, monkeypatch):
    from gateway.conversations import Session

    app, *_ = setup(tmp_path)
    second = 'next-call-segment-0002'
    emit = Session.emit
    next_ready = asyncio.Event()

    async def slow_saved(self, event, **fields):
        await emit(self, event, **fields)
        if event == 'turn.saved' and fields['turn']['id'] == RID:
            await asyncio.wait_for(next_ready.wait(), 3)
        if event == 'input.ready' and fields['input_id'] == second:
            next_ready.set()

    monkeypatch.setattr(Session, 'emit', slow_saved)
    with TestClient(app) as client, client.websocket_connect('/v3/conversations/xing/stream') as ws:
        hello(ws)
        ws.send_json(dict(command='input.start', input_id=RID, kind='call'))
        until(ws, 'input.ready')
        pcm(ws)
        ws.send_json(dict(command='input.commit', input_id=RID))
        until(ws, 'turn.saved')
        ws.send_json(dict(command='input.start', input_id=second, kind='call'))
        assert receive(ws)['event'] == 'input.ready'
        pcm(ws, rid=second)
        ws.send_json(dict(command='input.commit', input_id=second))
        assert until(ws, 'turn.saved')[-1]['turn']['id'] == second
        assert [r['id'] for r in app.state.conversations.store.rows('xing')] == [RID, second]
