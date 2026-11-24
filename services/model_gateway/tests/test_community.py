"""Two-account acceptance with only synthetic cards, PCM and mock providers."""
import sqlite3

from fastapi.testclient import TestClient

from gateway.app import create_app
from gateway.conversation_store import ConversationStore
from gateway.providers import Providers, Settings
from test_conversations import ASR, RID, TOKEN, pcm, receive, text, until


class PersonaRecorder(Providers):
    def __init__(self, settings):
        super().__init__(settings)
        self.inputs = []

    async def reply(self, character, history, content, *, persona=None):
        self.inputs.append((character, history, persona))
        yield '模拟回复'


def credentials(client, name):
    response = client.post('/community/register', json={'username': name, 'password': 'test password'})
    assert response.status_code == 201
    return {'Authorization': 'Bearer ' + response.json()['token']}


def start(socket, headers):
    socket.send_json({'command':'session.start', 'token':headers['Authorization'].split()[1]})
    return receive(socket)


def test_two_accounts_forum_import_and_voice(tmp_path):
    settings = Settings(mode='mock', token=TOKEN, data_dir=str(tmp_path), community_enabled=True)
    recorder = PersonaRecorder(settings)
    with TestClient(create_app(settings, recorder, asr=ASR())) as client:
        a, b = credentials(client, '作者'), credentials(client, '读者')
        assert client.post('/community/login', json={'username':'作者','password':'incorrect'}).status_code == 401
        assert client.post('/community/posts', json={'body':'匿名'}).status_code == 401
        card = dict(name='小海',description='潮汐观察员',persona='喜欢潮汐',avatar='sprout',voice='bright')
        owned = client.post('/community/characters', headers=a, json=card).json()['id']
        post = client.post('/community/posts', headers=a, json={'character_id':owned,'body':'我的角色'}).json()
        assert post['card'] == card
        path = '/community/posts/' + str(post['id'])
        share = '/community/shares/' + post['share']
        assert client.get('/s/'+post['share']).status_code == 200
        assert client.get(share).json()['card'] == card
        client.put('/community/characters/'+owned, headers=a, json=dict(card, name='已改名'))
        assert client.get(share).json()['card']['name'] == '小海'
        assert client.delete(path, headers=b).status_code == 404
        assert client.post('/community/posts', headers=b, json={'character_id':owned,'body':'测试'}).status_code == 404
        clone = client.post(share+'/import', headers=b).json()['id']
        assert clone != owned and client.post(share+'/import', headers=b).json()['id'] == clone
        assert client.get('/community/characters', headers=b).json()['items'][-1]['id'] == clone
        comment = client.post(path+'/comments', headers=b, json={'body':'你好'}).json()['id']
        client.post(path+'/comments', headers=a, json={'body':'谢谢','parent_id':comment}).raise_for_status()
        assert client.delete(f'{path}/comments/{comment}', headers=a).status_code == 404
        client.delete(f'{path}/comments/{comment}', headers=b).raise_for_status()
        replies = client.get(path+'/comments').json()['items']
        assert replies[0]['body'] is None and replies[1]['parent'] == comment
        client.delete(path, headers=a).raise_for_status()
        assert client.post(share+'/import', headers=b).status_code == 404

        bind = '/community/characters/sprout/voice-binding'
        client.put(bind, headers=a, json={'profile_id':'bright', 'revision':0}).raise_for_status()
        assert client.get(bind, headers=b).json()['profile_id'] is None
        assert client.get('/v1/voice-profiles', headers=b).status_code == 401
        ws = '/v3/conversations/sprout/stream'
        with client.websocket_connect(ws) as first, client.websocket_connect(ws) as second:
            assert start(first,a)['history'] == start(second,b)['history'] == []
            text(first,'A 的私聊',speak=False)
            until(first,'turn.completed')
            text(second,'B 的私聊',speak=False)
            until(second,'turn.completed')
            assert recorder.inputs[-1][1] == []
            rid = 'recording-private-owner-001'
            first.send_json({'command':'input.start','input_id':rid,'kind':'hold'})
            until(first,'input.ready')
            pcm(first,rid)
            first.send_json({'command':'input.commit','input_id':rid})
            until(first,'audio.completed')
            assert client.get('/v3/recordings/'+rid, headers=a).status_code == 200
            assert client.get('/v3/recordings/'+rid, headers=b).status_code == 404
        for headers, prompt in [(a,'A 的私聊'),(b,'B 的私聊')]:
            rows = client.get('/v3/conversations/sprout',headers=headers).json()['items']
            assert rows[0]['id'] == RID and rows[0]['prompt'] == prompt
        with client.websocket_connect(f'/v3/conversations/{clone}/stream') as imported:
            assert start(imported,b)['history'] == []
            text(imported, rid='new-imported-text-0001', speak=False)
            until(imported,'turn.completed')
            assert '喜欢潮汐' in recorder.inputs[-1][2]
            for kind in ('hold','call'):
                rid = 'synthetic-imported-'+kind
                imported.send_json({'command':'input.start','input_id':rid,'kind':kind})
                until(imported,'input.ready')
                pcm(imported,rid)
                imported.send_json({'command':'input.commit','input_id':rid})
                until(imported,'audio.completed')
                assert '喜欢潮汐' in recorder.inputs[-1][2]
            client.post('/community/logout', headers=b).raise_for_status()
        assert client.get('/community/me', headers=b).status_code == 401
        login = client.post('/community/login',json={'username':'读者','password':'test password'}).json()
        restored = {'Authorization': 'Bearer '+login['token']}
        assert clone in [r['id'] for r in client.get('/community/characters',headers=restored).json()['items']]
        assert client.get('/v3/conversations/'+clone,headers=a).status_code == 404


def test_search_public_snapshots_and_paginate_matching_posts(tmp_path):
    settings = Settings(mode='mock', token=TOKEN, data_dir=str(tmp_path), community_enabled=True)
    with TestClient(create_app(settings)) as client:
        owner = credentials(client, '搜索作者')
        card = dict(name='Sea%_海盐', description='沿岸', persona='散步', avatar='moon', voice='default')
        owned = client.post('/community/characters', headers=owner, json=card).json()['id']

        def matches(q, **params):
            response = client.get('/community/posts', params={'q': q, **params})
            response.raise_for_status()
            return [row['id'] for row in response.json()['items']]

        assert matches('海盐') == []
        shared = client.post('/community/posts', headers=owner,
                             json={'body': '潮汐', 'character_id': owned}).json()['id']
        client.put(f'/community/characters/{owned}', headers=owner, json=dict(card, name='私下改名')).raise_for_status()
        assert matches('  sea%_海  ') == [shared]
        assert matches('私下改名') == []
        ids = [shared]
        for i in range(32):
            body = '潮汐 &+笔记' if i % 2 == 0 else '潮汐'
            ids.append(client.post('/community/posts', headers=owner, json={'body': body}).json()['id'])
            client.post('/community/posts', headers=owner, json={'body': '无关讨论'}).raise_for_status()
        assert matches('%_') == [shared]
        assert matches('&+') == list(reversed(ids[1::2]))
        first = matches('潮汐')
        assert len(first) == 30
        assert first + matches('潮汐', before=first[-1]) == ids[::-1]
        feed = client.get('/community/posts').json()['items']
        assert matches('   ') == [row['id'] for row in feed]
        client.delete(f'/community/posts/{shared}', headers=owner).raise_for_status()
        assert matches('海盐') == []
        assert client.get('/community/posts', params={'q': 'x' * 101}).status_code == 422


def test_domain_association_and_dev_gateway_opt_in(tmp_path, monkeypatch):
    settings = Settings(mode='mock', token=TOKEN, data_dir=str(tmp_path))
    with TestClient(create_app(settings)) as client:
        assert client.get('/community/posts').status_code == 404
    settings.community_enabled = True
    monkeypatch.setenv('COMMUNITY_ANDROID_CERT_SHA256', ':'.join(['AA'] * 32))
    monkeypatch.setenv('COMMUNITY_IOS_TEAM_ID', 'TESTTEAM01')
    with TestClient(create_app(settings)) as client:
        assert client.get('/.well-known/assetlinks.json').json()[0]['target']['package_name'] == 'dev.erciyuan.mobile'
        assert client.get('/.well-known/apple-app-site-association').json()['applinks']['details'][0]['components'] == [{'/':'/s/*'}]


def test_existing_development_history_stays_private(tmp_path):
    db = sqlite3.connect(tmp_path/'conversations-v3.sqlite')
    db.execute("""CREATE TABLE conversation_turns(id TEXT PRIMARY KEY,character TEXT,kind TEXT,prompt TEXT,
        reply TEXT,state TEXT,audio_state TEXT,played_frames INTEGER,total_frames INTEGER,recording BLOB,
        fingerprint TEXT,code TEXT,created REAL)""")
    db.execute("INSERT INTO conversation_turns VALUES ('old','xing','text','before upgrade','','complete','disabled',0,0,NULL,'','',0)")
    db.commit()
    db.close()
    store = ConversationStore(tmp_path)
    assert store.rows('xing')[0]['prompt'] == 'before upgrade'
    assert not store.scoped('new-account').rows('xing')
    store.close()
