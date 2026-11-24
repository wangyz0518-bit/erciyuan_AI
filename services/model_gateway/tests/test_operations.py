"""Operator permissions, moderation visibility, support ownership and aggregate usage."""
import time

from fastapi.testclient import TestClient

from gateway.app import create_app
from gateway.providers import Settings
from test_community import credentials


def test_operator_workflow(tmp_path, monkeypatch):
    settings = Settings(mode='mock', token='mock-operations-test-token', data_dir=str(tmp_path),
                        community_enabled=True)
    app = create_app(settings)
    with TestClient(app) as client:
        admin = credentials(client, '运营')
        owner = credentials(client, '作者')
        reader = credentials(client, '读者')
        admin_id = client.get('/community/me', headers=admin).json()['id']
        overview = '/ops/api/overview'
        assert client.get('/ops/').status_code == 200
        assert client.get('/ops/assets/console.js').status_code == 200
        assert client.get(overview).status_code == 401
        monkeypatch.setenv('COMMUNITY_ADMIN_IDS', '运营')
        assert client.get(overview, headers=admin).status_code == 403
        monkeypatch.setenv('COMMUNITY_ADMIN_IDS', admin_id)
        assert client.get(overview, headers=reader).status_code == 403
        assert client.get('/ops/api/tickets?queue=reports', headers=reader).status_code == 403

        post = client.post('/community/posts', headers=owner,
                           json={'body': '公开说明', 'character_id': 'sprout'}).json()
        post_id = post['id']
        comments = f'/community/posts/{post_id}/comments'
        share = '/community/shares/' + post['share']
        copied = client.post(share + '/import', headers=reader).json()['id']
        cid = client.post(comments, headers=owner, json={'body': '公开评论'}).json()['id']
        report = {'post_id': post_id, 'message': '请复核帖子'}
        assert client.post('/community/reports', json=report).status_code == 401
        pid = client.post('/community/reports', headers=reader, json=report).json()['id']
        assert client.post('/community/reports', headers=reader, json=report).json()['id'] == pid
        crid = client.post('/community/reports', headers=reader, json=dict(report, comment_id=cid)).json()['id']
        fid = client.post('/community/feedback', headers=reader, json={'message':'使用建议'}).json()['id']
        assert client.get('/community/tickets', headers=owner).json()['items'] == []
        assert len(client.get('/community/tickets', headers=reader).json()['items']) == 3
        page = client.get('/ops/api/tickets?queue=reports', headers=admin).json()
        assert len(page['items']) == 2 and page['items'][1]['evidence']['card']['name'] == '小芽'
        assert client.get(overview, headers=admin).json()['pending'] == {'reports': 2, 'feedback': 1}

        def resolve(ticket, action, headers=admin):
            return client.post(f'/ops/api/tickets/{ticket}/resolve', headers=headers,
                               json={'action': action, 'message': '已完成核对'})
        assert resolve(pid, 'hide', owner).status_code == 403
        assert resolve(fid, 'hide').status_code == 422
        assert resolve(crid, 'hide').status_code == 200
        assert client.get(comments).json()['items'][0]['body'] is None
        assert client.post(comments, headers=owner, json={'body': '回复', 'parent_id': cid}).status_code == 404
        assert resolve(pid, 'hide').status_code == 200
        assert resolve(pid, 'dismiss').status_code == 409
        assert client.get('/community/posts').json()['items'] == []
        for path in (f'/community/posts/{post_id}', comments, share, '/s/' + post['share']):
            assert client.get(path).status_code == 404
        assert client.post(share + '/import', headers=owner).status_code == 404
        assert copied in [c['id'] for c in client.get('/community/characters', headers=reader).json()['items']]
        assert resolve(fid, 'reply').status_code == 200
        mine = client.get('/community/tickets', headers=reader).json()['items']
        assert mine[0]['reply'] == '已完成核对' and 'evidence' not in mine[0]
        closed = client.get('/ops/api/tickets?queue=feedback&status=closed', headers=admin).json()['items']
        assert closed[0]['handler'] == '运营'
        separate = client.post('/community/posts', headers=owner, json={'body':'第二篇'}).json()['id']
        dismissed = client.post('/community/reports', headers=reader,
                                json=dict(report, post_id=separate)).json()['id']
        assert resolve(dismissed, 'dismiss').status_code == 200
        assert client.get(f'/community/posts/{separate}').status_code == 200

        history = app.state.conversations.store
        user = history.scoped(client.get('/community/me', headers=reader).json()['id'])
        for kind in ('text','hold','call'):
            user.begin(kind, 'sprout', kind, '仅测试的私密文字')
        history.begin('guest','sprout','text','开发空间')
        user.begin('old','sprout','text','较早历史')
        with history.db:
            history.db.execute("UPDATE conversation_turns SET created=? WHERE id='old'", (time.time()-15*86400,))
        stats = client.get(overview + '?days=7', headers=admin)
        assert stats.headers['cache-control'] == 'no-store'
        assert sum(day['text'] for day in stats.json()['usage']) == 1
        assert sum(day['voice'] for day in stats.json()['usage']) == 2
        assert '仅测试的私密文字' not in stats.text
        stats30 = client.get(overview + '?days=30', headers=admin).json()
        assert sum(day['text'] for day in stats30['usage']) == 2
        monkeypatch.delenv('COMMUNITY_ADMIN_IDS')
        assert client.get(overview, headers=admin).status_code == 403


def test_distinct_ticket_pages_survive_restart(tmp_path, monkeypatch):
    settings = Settings(mode='mock', token='mock-operations-test-token', data_dir=str(tmp_path),
                        community_enabled=True)
    with TestClient(create_app(settings)) as client:
        admin, a, b = (credentials(client, name) for name in ('审核员', '用户甲', '用户乙'))
        monkeypatch.setenv('COMMUNITY_ADMIN_IDS', client.get('/community/me', headers=admin).json()['id'])
        for i in range(32):
            author = a if i % 2 else b
            client.post('/community/feedback', headers=author, json={'message': f'建议 {i}'}).raise_for_status()

    with TestClient(create_app(settings)) as client:
        path = '/ops/api/tickets?queue=feedback'
        first = client.get(path, headers=admin).json()
        second = client.get(f"{path}&before={first['next_before']}", headers=admin).json()
        ids = [row['id'] for row in first['items'] + second['items']]
        assert len(first['items']) == 30 and len(second['items']) == 2
        assert ids == sorted(set(ids), reverse=True) and second['next_before'] is None
        mine = client.get('/community/tickets', headers=a).json()
        assert len(mine['items']) == 16 and mine['next_before'] is None
