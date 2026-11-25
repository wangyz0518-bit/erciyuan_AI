"""Synthetic accounts, a real database and the same v3 entry points as the app."""
import base64
import io
import json

from fastapi.testclient import TestClient
from PIL import Image

from gateway import usage
from gateway.account_data import TABLES
from gateway.app import create_app
from gateway.providers import Settings
from test_community import PersonaRecorder, credentials, start
from test_conversations import TOKEN, text, until


def test_assets_memory_discovery_and_notifications(tmp_path, monkeypatch):
    settings = Settings(mode='mock', token=TOKEN, data_dir=str(tmp_path), community_enabled=True)
    recorder = PersonaRecorder(settings)
    with TestClient(create_app(settings, recorder)) as client:
        author, reader = credentials(client, '海盐作者'), credentials(client, '海盐读者')
        owner = client.get('/community/me', headers=author).json()['id']
        options = {owner: [{'id': 'private-mine', 'name': '我的音色', 'provider_id': 'test-provider'}]}
        monkeypatch.setenv('COMMUNITY_PRIVATE_VOICES', json.dumps(options))
        base = '/community/characters/sprout'
        pic = io.BytesIO()
        Image.new('RGB', (7, 8), '#72ad78').save(pic, format='PNG')
        portrait = client.put(base+'/portrait', headers=author,
                              json={'image': base64.b64encode(pic.getvalue()).decode()}).json()['portrait']
        assert Image.open(io.BytesIO(base64.b64decode(portrait))).size == (7, 8)
        assert client.put(base+'/portrait', headers=author,json={'image':'bad'}).status_code == 422
        client.put(base+'/voice-binding', headers=author,
                   json={'profile_id':'private-mine','revision':0}).raise_for_status()
        assert client.post('/community/voices/private-mine/preview', headers=reader).status_code == 404
        assert 'test-provider' not in client.get('/community/voices', headers=author).text
        client.post('/community/posts', headers=author, json={'body':'普通讨论'}).raise_for_status()
        def share(expose):
            return client.post('/community/posts', headers=author,
                json={'character_id':'sprout', 'body':'合成测试角色','share_portrait':expose}).json()
        assert 'portrait' not in share(False)['card']
        post = share(True)
        assert post['card']['portrait'] == portrait and 'private-mine' not in str(post)
        assert all(p['card'] for p in client.get('/community/posts?roles_only=true').json()['items'])
        imported = client.post('/community/shares/'+post['share']+'/import',headers=reader).json()
        assert imported['portrait'] == portrait
        cid = imported['id']
        memories = '/community/characters/'+cid+'/memories'
        mid = client.post(memories,headers=reader,json={'text':'旧资料'}).json()['id']
        assert client.put(f'{memories}/{mid}',headers=author,json={'text':'越权'}).status_code == 404
        client.put(f'{memories}/{mid}',headers=reader,json={'text':'更正资料'}).raise_for_status()
        with client.websocket_connect('/v3/conversations/'+cid+'/stream') as ws:
            start(ws,reader)
            text(ws, '你好', speak=False)
            until(ws, 'turn.completed')
            assert '更正资料' in recorder.inputs[-1][2] and '旧资料' not in recorder.inputs[-1][2]
            client.delete(f'{memories}/{mid}',headers=reader).raise_for_status()
            text(ws,'第二条',rid='test-memory-next-0002', speak=False)
            until(ws,'turn.completed')
            assert '更正资料' not in recorder.inputs[-1][2]
        path = f"/community/posts/{post['id']}"
        first = client.post(path+'/comments',headers=reader,json={'body':'评论'}).json()['id']
        reply = client.post(path+'/comments',headers=author,json={'body':'回复','parent_id':first}).json()['id']
        notices = '/community/notifications'
        notice = client.get(notices,headers=reader).json()['items'][0]
        assert notice['comment'] == reply and notice['seen'] == 0
        assert client.post(f"{notices}/{notice['id']}/open",headers=author).status_code == 404
        assert client.post(f"{notices}/{notice['id']}/open",headers=reader).json()['seen'] == 1
        client.delete(path,headers=author).raise_for_status()
        assert client.get(notices,headers=reader).json()['items'] == []


def test_recovery_backup_and_deletion_are_owner_scoped(tmp_path):
    settings=Settings(mode='mock',token=TOKEN,data_dir=str(tmp_path),community_enabled=True)
    with TestClient(create_app(settings)) as c:
        a,b=credentials(c,'备份账户'),credentials(c,'独立账户')
        owner=c.get('/community/me',headers=a).json()['id']
        snap=dict(format='erciyuan-person-memory-export',schema_version=1,owner_id=owner,
                  database_schema_version=5,attachments=[],**{t:[] for t in TABLES})
        path='/community/account'
        assert c.put(path+'/backup',headers=b,json=snap).status_code == 422
        c.put(path+'/backup',headers=a,json=snap).raise_for_status()
        assert c.get(path+'/backup',headers=a).json()['snapshot'] == snap
        assert c.get(path+'/backup',headers=b).status_code == 404
        password={'password':'test password'}
        code=c.post(path+'/recovery-code',headers=a,json=password).json()['code']
        reset={'username':'备份账户','code':code,'password':'a new password'}
        c.post(path+'/reset',json=reset).raise_for_status()
        assert c.post(path+'/reset',json=reset).status_code == 401
        assert c.get('/community/me',headers=a).status_code == 401
        token=c.post('/community/login',json={'username':reset['username'],'password':reset['password']}).json()['token']
        a={'Authorization':'Bearer '+token}
        post=c.post('/community/posts',headers=a,json={'body':'角色','character_id':'sprout'}).json()
        clone=c.post('/community/shares/'+post['share']+'/import',headers=b).json()['id']
        service=c.app.state.conversations
        service.store.scoped(owner).begin('private-test-recording','sprout','hold','私有',b'synthetic')
        assert c.request('DELETE',path,headers=a,json=password).status_code == 401
        c.request('DELETE',path,headers=a,json={'password':reset['password']}).raise_for_status()
        assert service.store.scoped(owner).rows('sprout') == []
        assert c.get('/community/me',headers=a).status_code==401
        assert c.get('/s/'+post['share']).status_code==404
        assert clone in [x['id'] for x in c.get('/community/characters',headers=b).json()['items']]
        assert not service.community.db.execute('SELECT owner FROM device_backups WHERE owner=?',(owner,)).fetchone()


def test_costs_record_missing_data_failure_and_mock_separately(tmp_path,monkeypatch):
    settings=Settings(mode='mock',token=TOKEN,data_dir=str(tmp_path),community_enabled=True)
    with TestClient(create_app(settings)) as client:
        a=credentials(client,'运营测试')
        monkeypatch.setenv('COMMUNITY_ADMIN_IDS',client.get('/community/me',headers=a).json()['id'])
        svc=client.app.state.conversations
        client.post('/community/voices/default/preview',headers=a).raise_for_status()
        live=Settings(mode='live')
        monkeypatch.setenv('COMMUNITY_RATE_MODEL','2')
        with usage.call(svc.community,live,'model'):
            usage.record_tokens(1500)
        try:
            with usage.call(svc.community,live,'tts'):
                raise ValueError('synthetic failure')
        except ValueError:
            pass
        rows=client.get('/ops/api/overview',headers=a).json()['providers']
        mock,= [r for r in rows if r['mode']=='mock']
        assert mock['estimated_cny']==0 and mock['quantity']>0
        model,= [r for r in rows if r['kind']=='model']
        assert model['estimated_cny']==3 and model['calls']==1
        speech,= [r for r in rows if r['kind']=='tts' and r['mode']=='live']
        assert speech['failed']==1 and speech['estimated_cny'] is None and speech['unknown_quantity']==1
