"""Accounts, public role snapshots and owner-scoped character libraries."""
import asyncio
import hashlib
import hmac
import html
import json
import os
import re
import secrets
import sqlite3
import time
from pathlib import Path
from typing import Literal

from fastapi import Depends, Header, HTTPException, Query, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, ConfigDict, Field

from . import operations
from .providers import PERSONAS

PRESETS = {'default': '默认', 'bright': '明快'}
STARTERS = {
    'xing': ('小星', '温柔而好奇的伙伴', 'star'),
    'yue': ('小月', '善于倾听的伙伴', 'moon'),
    'sprout': ('小芽', '软萌又好奇的伙伴', 'sprout'),
}


class Input(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)


class Credentials(BaseModel):
    model_config = ConfigDict(extra='forbid')
    username: str = Field(min_length=2, max_length=32)
    password: str = Field(min_length=8, max_length=128)


class Card(Input):
    name: str = Field(min_length=1, max_length=48)
    description: str = Field(min_length=1, max_length=240)
    persona: str = Field(min_length=1, max_length=2000)
    avatar: Literal['star', 'moon', 'sprout']
    voice: Literal['default', 'bright']


class Post(Input):
    body: str = Field(min_length=1, max_length=3000)
    character_id: str | None = Field(default=None, max_length=64)


class Comment(Input):
    body: str = Field(min_length=1, max_length=1000)
    parent_id: int | None = Field(default=None, ge=1)


class Binding(Input):
    profile_id: Literal['default', 'bright'] | None = None
    revision: int = Field(ge=0)


def new_id():
    return secrets.token_hex(16)


def password_hash(password, salt):
    return hashlib.scrypt(password.encode(), salt=salt, n=2**15, r=8, p=1, maxmem=64*1024*1024)


def token_hash(token):
    return hashlib.sha256(token.encode()).hexdigest()


class Community:
    def __init__(self, directory):
        self.db = sqlite3.connect(Path(directory) / 'community.sqlite', check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.executescript("""
            PRAGMA foreign_keys=ON;
            CREATE TABLE IF NOT EXISTS accounts(
                id TEXT PRIMARY KEY, username TEXT NOT NULL, login TEXT UNIQUE NOT NULL,
                salt BLOB NOT NULL, digest BLOB NOT NULL);
            CREATE TABLE IF NOT EXISTS sessions(
                token TEXT PRIMARY KEY, owner TEXT NOT NULL REFERENCES accounts(id), expires REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS attempts(bucket TEXT PRIMARY KEY, since REAL, attempts INTEGER);
            CREATE TABLE IF NOT EXISTS library(
                owner TEXT NOT NULL REFERENCES accounts(id), id TEXT NOT NULL, card TEXT NOT NULL,
                source TEXT, binding TEXT, revision INTEGER DEFAULT 0,
                PRIMARY KEY(owner,id), UNIQUE(owner,source));
            CREATE TABLE IF NOT EXISTS posts(
                id INTEGER PRIMARY KEY AUTOINCREMENT, author TEXT NOT NULL REFERENCES accounts(id),
                body TEXT NOT NULL, share TEXT UNIQUE, snapshot TEXT, created INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS comments(
                id INTEGER PRIMARY KEY AUTOINCREMENT, post INTEGER REFERENCES posts(id) ON DELETE CASCADE,
                author TEXT NOT NULL REFERENCES accounts(id), body TEXT, parent INTEGER, created INTEGER NOT NULL);
            CREATE INDEX IF NOT EXISTS comments_by_post ON comments(post,id);
        """)
        operations.initialize(self.db)

    def user(self, token):
        if not isinstance(token, str) or len(token) != 64:
            return None
        row = self.db.execute('''SELECT a.id,a.username FROM sessions s JOIN accounts a ON a.id=s.owner
            WHERE token=? AND expires>?''', (token_hash(token), time.time())).fetchone()
        return dict(row) if row else None

    def role(self, owner, character):
        row = self.db.execute('SELECT * FROM library WHERE owner=? AND id=?', (owner, character)).fetchone()
        if not row:
            raise HTTPException(404, 'CHARACTER_NOT_FOUND')
        return dict(row)

    def post(self, *, pid=None, share=None):
        row = self.db.execute('''SELECT p.*,a.username FROM visible_posts p JOIN accounts a ON p.author=a.id
            WHERE p.id=? OR p.share=?''', (pid, share)).fetchone()
        if not row:
            raise HTTPException(404, 'POST_NOT_FOUND')
        return self.public(row)

    @staticmethod
    def public(row):
        return {k: row[k] for k in ('id', 'username', 'body', 'share', 'created')} | {
            'card': json.loads(row['snapshot']) if row['snapshot'] else None}

    def limit(self, bucket):
        now = time.time()
        with self.db:
            self.db.execute('DELETE FROM attempts WHERE since<?', (now-300,))
            self.db.execute('''INSERT INTO attempts VALUES (?,?,1)
                ON CONFLICT(bucket) DO UPDATE SET attempts=attempts+1''', (bucket, now))
            count = self.db.execute('SELECT attempts FROM attempts WHERE bucket=?', (bucket,)).fetchone()[0]
        if count > 30:
            raise HTTPException(429, 'TRY_LATER')

    def start_session(self, owner, username):
        token = secrets.token_hex(32)
        with self.db:
            self.db.execute('DELETE FROM sessions WHERE expires<=?', (time.time(),))
            self.db.execute('INSERT INTO sessions VALUES (?,?,?)', (token_hash(token), owner, time.time()+30*86400))
        return {'id': owner, 'username': username, 'token': token}


def register(app, store):
    db = store.db
    def bearer(header):
        return header[7:] if header.startswith('Bearer ') else ''

    async def account(authorization: str = Header(default='')):
        user = store.user(bearer(authorization))
        if not user:
            raise HTTPException(401, 'LOGIN_REQUIRED')
        return user

    operations.register(app, store, account)

    @app.post('/community/register', status_code=201)
    async def signup(data: Credentials, request: Request):
        username = data.username.strip()
        if not re.fullmatch(r'[\w.-]{2,32}', username):
            raise HTTPException(422, 'INVALID_USERNAME')
        store.limit(request.client.host)
        owner, salt = new_id(), os.urandom(16)
        digest = await asyncio.to_thread(password_hash, data.password, salt)
        try:
            with db:
                db.execute('INSERT INTO accounts VALUES (?,?,?,?,?)',
                           (owner, username, username.casefold(), salt, digest))
                for role, (name, desc, avatar) in STARTERS.items():
                    card = Card(name=name, description=desc, persona=PERSONAS[role], avatar=avatar, voice='default')
                    db.execute('INSERT INTO library(owner,id,card) VALUES (?,?,?)', (owner, role, card.model_dump_json()))
        except sqlite3.IntegrityError:
            raise HTTPException(409, 'USERNAME_TAKEN') from None
        return store.start_session(owner, username)

    @app.post('/community/login')
    async def login(data: Credentials, request: Request):
        store.limit(request.client.host)
        row = db.execute('SELECT * FROM accounts WHERE login=?', (data.username.strip().casefold(),)).fetchone()
        digest = await asyncio.to_thread(password_hash, data.password, row['salt'] if row else bytes(16))
        if not row or not hmac.compare_digest(row['digest'], digest):
            raise HTTPException(401, 'INVALID_CREDENTIALS')
        return store.start_session(row['id'], row['username'])

    @app.get('/community/me')
    async def me(user=Depends(account)):
        return user

    @app.post('/community/logout')
    async def logout(authorization: str = Header(default='')):
        with db:
            db.execute('DELETE FROM sessions WHERE token=?', (token_hash(bearer(authorization)),))
        await app.state.conversations.revoke(bearer(authorization))
        return {'ok': True}

    @app.get('/community/characters')
    async def library(user=Depends(account)):
        rows = db.execute('SELECT id,card FROM library WHERE owner=? ORDER BY rowid', (user['id'],))
        return {'items': [dict(id=r['id'], **json.loads(r['card'])) for r in rows]}

    @app.put('/community/migrations/{cid}')
    async def migrate_character(cid: str, data: Card, user=Depends(account)):
        if not re.fullmatch(r'm-[a-f0-9]{32}', cid):
            raise HTTPException(422, 'INVALID_CHARACTER')
        with db:
            db.execute('INSERT INTO library(owner,id,card) VALUES (?,?,?) ON CONFLICT(owner,id) DO NOTHING',
                       (user['id'], cid, data.model_dump_json()))
        return {'id': cid}

    @app.post('/community/characters', status_code=201)
    async def create_card(data: Card, user=Depends(account)):
        cid = new_id()
        with db:
            db.execute('INSERT INTO library(owner,id,card) VALUES (?,?,?)', (user['id'], cid, data.model_dump_json()))
        return {'id': cid, **data.model_dump()}

    @app.put('/community/characters/{cid}')
    async def update_card(cid: str, data: Card, user=Depends(account)):
        store.role(user['id'], cid)
        with db:
            db.execute('UPDATE library SET card=? WHERE owner=? AND id=?', (data.model_dump_json(), user['id'], cid))
        return {'id': cid, **data.model_dump()}

    @app.get('/community/voices')
    async def voices(user=Depends(account)):
        return {'items': [dict(id=k, name=v, status='ready') for k, v in PRESETS.items()]}

    @app.get('/community/characters/{cid}/voice-binding')
    async def binding(cid: str, user=Depends(account)):
        row = store.role(user['id'], cid)
        return dict(profile_id=row['binding'], revision=row['revision'], character_id=cid)

    @app.put('/community/characters/{cid}/voice-binding')
    async def bind(cid: str, data: Binding, user=Depends(account)):
        store.role(user['id'], cid)
        with db:
            changed = db.execute('UPDATE library SET binding=?, revision=revision+1 WHERE owner=? AND id=? AND revision=?',
                                 (data.profile_id, user['id'], cid, data.revision)).rowcount
        if not changed:
            raise HTTPException(409, 'REVISION_CONFLICT')
        return await binding(cid, user)

    @app.get('/community/posts')
    async def feed(before: int | None = Query(None, ge=1)):
        rows = db.execute('''SELECT p.*,a.username FROM visible_posts p JOIN accounts a ON p.author=a.id
            WHERE (? IS NULL OR p.id<?) ORDER BY p.id DESC LIMIT 30''', (before, before))
        return {'items': [store.public(r) for r in rows]}

    @app.post('/community/posts', status_code=201)
    async def publish(data: Post, user=Depends(account)):
        card = store.role(user['id'], data.character_id)['card'] if data.character_id else None
        with db:
            pid = db.execute('INSERT INTO posts(author,body,share,snapshot,created) VALUES (?,?,?,?,?)',
                             (user['id'], data.body, new_id() if card else None, card, int(time.time()))).lastrowid
        return store.post(pid=pid)

    @app.get('/community/posts/{pid}')
    async def detail(pid: int):
        return store.post(pid=pid)

    @app.delete('/community/posts/{pid}')
    async def remove_post(pid: int, user=Depends(account)):
        with db:
            if not db.execute('DELETE FROM posts WHERE id=? AND author=?', (pid, user['id'])).rowcount:
                raise HTTPException(404, 'POST_NOT_FOUND')
        return {'ok': True}

    @app.get('/community/posts/{pid}/comments')
    async def comments(pid: int, after: int = Query(0, ge=0)):
        store.post(pid=pid)
        rows = db.execute('''SELECT c.id,c.body,c.parent,c.created,a.username FROM visible_comments c
            JOIN accounts a ON a.id=c.author WHERE c.post=? AND c.id>? ORDER BY c.id LIMIT 50''', (pid, after))
        return {'items': [dict(row) for row in rows]}

    @app.post('/community/posts/{pid}/comments', status_code=201)
    async def comment(pid: int, data: Comment, user=Depends(account)):
        store.post(pid=pid)
        with db:
            if data.parent_id and not db.execute('SELECT 1 FROM visible_comments WHERE post=? AND id=? AND body IS NOT NULL',
                                                  (pid, data.parent_id)).fetchone():
                raise HTTPException(404, 'COMMENT_NOT_FOUND')
            cid = db.execute('INSERT INTO comments(post,author,body,parent,created) VALUES (?,?,?,?,?)',
                             (pid, user['id'], data.body, data.parent_id, int(time.time()))).lastrowid
        return {'id': cid}

    @app.delete('/community/posts/{pid}/comments/{cid}')
    async def remove_comment(pid: int, cid: int, user=Depends(account)):
        with db:
            if not db.execute('UPDATE comments SET body=NULL WHERE post=? AND id=? AND author=?',
                              (pid, cid, user['id'])).rowcount:
                raise HTTPException(404, 'COMMENT_NOT_FOUND')
        return {'ok': True}

    @app.get('/community/shares/{share}')
    async def preview(share: str):
        return store.post(share=share)

    @app.post('/community/shares/{share}/import')
    async def import_role(share: str, user=Depends(account)):
        with db:
            db.execute('''INSERT INTO library(owner,id,card,source)
                SELECT ?,?,snapshot,share FROM visible_posts WHERE share=?
                ON CONFLICT(owner,source) DO NOTHING''', (user['id'], new_id(), share))
            store.post(share=share)
            row = db.execute('SELECT id,card FROM library WHERE owner=? AND source=?', (user['id'], share)).fetchone()
        return {'id': row['id'], **json.loads(row['card'])}

    @app.get('/.well-known/assetlinks.json')
    async def android_association():
        cert = os.getenv('COMMUNITY_ANDROID_CERT_SHA256', '')
        if not re.fullmatch(r'(?:[A-Fa-f0-9]{2}:){31}[A-Fa-f0-9]{2}', cert):
            raise HTTPException(404, 'DOMAIN_NOT_CONFIGURED')
        return [{'relation': ['delegate_permission/common.handle_all_urls'],
                 'target': {'namespace':'android_app', 'package_name':'dev.erciyuan.mobile',
                            'sha256_cert_fingerprints':[cert.upper()]}}]

    @app.get('/.well-known/apple-app-site-association')
    async def ios_association():
        team = os.getenv('COMMUNITY_IOS_TEAM_ID', '')
        if not re.fullmatch(r'[A-Z0-9]{10}', team):
            raise HTTPException(404, 'DOMAIN_NOT_CONFIGURED')
        return {'applinks': {'details':[{'appIDs':[team+'.dev.erciyuan.mobile'],
                                          'components':[{'/':'/s/*'}]}]}}

    @app.get('/s/{share}', response_class=HTMLResponse)
    async def landing(share: str):
        post = store.post(share=share)
        card = post['card']
        return HTMLResponse('<!doctype html><html lang="zh-CN"><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1"><title>角色分享</title>'
            '<main style="max-width:32em;margin:12vh auto;padding:1em;font:18px system-ui">'
            f'<p>{html.escape(post["username"])} 分享的角色</p><h1>{html.escape(card["name"])}</h1>'
            f'<p>{html.escape(card["description"])}</p><p>{html.escape(post["body"])}</p>'
            f'<a href="erciyuan://share/{post["share"]}">在 App 中打开角色卡</a>'
            '<p>也可复制本页链接，在 App 的社区中打开。</p></main></html>',
            headers={'Referrer-Policy': 'no-referrer', 'Cache-Control': 'no-store'})
