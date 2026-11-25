"""Community support tickets, moderation and the same-origin operator console."""
from . import usage as provider_usage

import json
import os
import time
from pathlib import Path
from typing import Literal

from fastapi import Depends, HTTPException, Query, Response
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, ConfigDict, Field


class Message(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    message: str = Field(min_length=1, max_length=1000)


class Report(Message):
    post_id: int = Field(ge=1)
    comment_id: int | None = Field(default=None, ge=1)


class Resolution(Message):
    action: Literal['hide', 'dismiss', 'reply']


def initialize(db):
    db.executescript("""
        CREATE TABLE IF NOT EXISTS support_tickets(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            reporter TEXT NOT NULL REFERENCES accounts(id),
            kind TEXT NOT NULL CHECK(kind IN ('post','comment','feedback')),
            target INTEGER, evidence TEXT, message TEXT NOT NULL, created INTEGER NOT NULL,
            action TEXT, reply TEXT, handler TEXT REFERENCES accounts(id), handled INTEGER,
            UNIQUE(reporter,kind,target));
        CREATE INDEX IF NOT EXISTS tickets_by_reporter ON support_tickets(reporter,id);
        CREATE INDEX IF NOT EXISTS tickets_by_action ON support_tickets(action,id);
        CREATE TABLE IF NOT EXISTS moderated_content(
            kind TEXT NOT NULL, target INTEGER NOT NULL, PRIMARY KEY(kind,target));
        CREATE VIEW IF NOT EXISTS visible_posts AS SELECT p.* FROM posts p
            WHERE NOT EXISTS (SELECT 1 FROM moderated_content m WHERE m.kind='post' AND m.target=p.id);
        CREATE VIEW IF NOT EXISTS visible_comments AS SELECT c.id,c.post,c.author,c.parent,c.created,
            CASE WHEN m.target IS NULL THEN c.body END AS body FROM comments c
            LEFT JOIN moderated_content m ON m.kind='comment' AND m.target=c.id;
    """)


def register(app, community, account):
    db = community.db

    async def operator(response: Response, user=Depends(account)):
        response.headers['Cache-Control'] = 'no-store'
        allowed = {value.strip() for value in os.getenv('COMMUNITY_ADMIN_IDS', '').split(',')}
        if user['id'] not in allowed:
            raise HTTPException(403, 'OPERATOR_REQUIRED')
        return user

    def ticket_page(sql, parameters):
        rows = list(db.execute(sql + ' ORDER BY t.id DESC LIMIT 31', parameters))
        return {'items': [dict(r) for r in rows[:30]],
                'next_before': rows[29]['id'] if len(rows) > 30 else None}

    @app.post('/community/reports')
    async def report(data: Report, user=Depends(account)):
        community.limit('support:' + user['id'])
        with db:
            post = community.post(pid=data.post_id)
            kind, target = 'post', post['id']
            evidence = {key: post[key] for key in ('username', 'body', 'card')}
            if data.comment_id is not None:
                row = db.execute('''SELECT a.username,c.body FROM visible_comments c
                    JOIN accounts a ON a.id=c.author WHERE c.id=? AND c.post=? AND c.body IS NOT NULL''',
                    (data.comment_id, post['id'])).fetchone()
                if not row:
                    raise HTTPException(404, 'COMMENT_NOT_FOUND')
                kind, target, evidence = 'comment', data.comment_id, dict(row)
            db.execute('''INSERT INTO support_tickets(reporter,kind,target,message,evidence,created)
                VALUES (?,?,?,?,?,?) ON CONFLICT(reporter,kind,target) DO NOTHING''',
                (user['id'], kind, target, data.message,
                 json.dumps(evidence, ensure_ascii=False), int(time.time())))
            ticket = db.execute('SELECT id FROM support_tickets WHERE reporter=? AND kind=? AND target=?',
                                (user['id'], kind, target)).fetchone()
        return {'id': ticket['id']}

    @app.post('/community/feedback', status_code=201)
    async def feedback(data: Message, user=Depends(account)):
        community.limit('support:' + user['id'])
        with db:
            ticket_id = db.execute("""INSERT INTO support_tickets(reporter,kind,message,created)
                VALUES (?,'feedback',?,?)""", (user['id'], data.message, int(time.time()))).lastrowid
        return {'id': ticket_id}

    @app.get('/community/tickets')
    async def own_tickets(response: Response, before: int | None = Query(None, ge=1), user=Depends(account)):
        response.headers['Cache-Control'] = 'no-store'
        return ticket_page('''SELECT t.id,t.kind,t.message,t.created,t.action,t.reply,t.handled
            FROM support_tickets t WHERE t.reporter=? AND (? IS NULL OR t.id<?)''',
            (user['id'], before, before))

    @app.get('/ops/api/overview')
    async def overview(days: int = Query(7, ge=1, le=30), user=Depends(operator)):
        now = int(time.time())
        # Calendar days in UTC, including today. Exclude the legacy guest/developer scope.
        today = now - now % 86400
        since = today - (days - 1) * 86400
        usage = app.state.conversations.store.daily_account_usage(since, time.time())
        pending = db.execute("""SELECT count(CASE WHEN kind<>'feedback' THEN 1 END) AS reports,
            count(CASE WHEN kind='feedback' THEN 1 END) AS feedback
            FROM support_tickets WHERE action IS NULL""").fetchone()
        return {'username': user['username'], 'pending': dict(pending), 'days': days,
                'since': since, 'usage': usage, 'providers': provider_usage.totals(db, since, now)}

    @app.get('/ops/api/tickets')
    async def tickets(queue: Literal['reports','feedback'], status: Literal['open','closed'] = 'open',
                      before: int | None = Query(None, ge=1), user=Depends(operator)):
        page = ticket_page('''SELECT t.id,t.kind,t.target,t.message,t.created,t.evidence,t.action,
            t.reply,t.handled,r.username AS reporter,h.username AS handler FROM support_tickets t
            JOIN accounts r ON t.reporter=r.id LEFT JOIN accounts h ON t.handler=h.id
            WHERE (t.kind='feedback')=? AND (t.action IS NULL)=? AND (? IS NULL OR t.id<?)''',
            (queue == 'feedback', status == 'open', before, before))
        for item in page['items']:
            if item['evidence']:
                item['evidence'] = json.loads(item['evidence'])
        return page

    @app.post('/ops/api/tickets/{ticket_id}/resolve')
    async def resolve(ticket_id: int, data: Resolution, user=Depends(operator)):
        with db:
            row = db.execute('SELECT kind,target,action FROM support_tickets WHERE id=?', (ticket_id,)).fetchone()
            if not row:
                raise HTTPException(404, 'TICKET_NOT_FOUND')
            if (row['kind'] == 'feedback') != (data.action == 'reply'):
                raise HTTPException(422, 'INVALID_RESOLUTION')
            changed = db.execute('''UPDATE support_tickets SET action=?,reply=?,handler=?,handled=?
                WHERE id=? AND action IS NULL''',
                (data.action, data.message, user['id'], int(time.time()), ticket_id)).rowcount
            if not changed:
                raise HTTPException(409, 'TICKET_ALREADY_HANDLED')
            if data.action == 'hide':
                db.execute('INSERT OR IGNORE INTO moderated_content(kind,target) VALUES (?,?)',
                           (row['kind'], row['target']))
        return {'id': ticket_id, 'action': data.action}

    assets = Path(__file__).with_name('operator_web')
    app.mount('/ops/assets', StaticFiles(directory=assets / 'assets'), name='operator-assets')

    @app.get('/ops/', include_in_schema=False)
    async def console():
        return FileResponse(assets / 'index.html', headers={
            'Cache-Control': 'no-store',
            'Content-Security-Policy': "default-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
            'Referrer-Policy': 'no-referrer',
        })
