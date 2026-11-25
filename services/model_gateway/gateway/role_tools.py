"""Private role memory and character media attached to the existing role card."""
import base64
import binascii
import io
import json
import os

from fastapi import Depends, HTTPException
from PIL import Image, ImageOps, UnidentifiedImageError
from pydantic import BaseModel, Field

from . import usage


class Memory(BaseModel):
    text: str = Field(min_length=1, max_length=500)


class Portrait(BaseModel):
    image: str | None = Field(default=None, max_length=3_000_000)


def thumbnail(value):
    try:
        raw = base64.b64decode(value, validate=True)
        with Image.open(io.BytesIO(raw), formats=['JPEG', 'PNG', 'WEBP']) as image:
            if image.width * image.height > 12_000_000 or image.width > 8192 or image.height > 8192:
                raise ValueError()
            image.thumbnail((320, 320))
            clean = ImageOps.exif_transpose(image).convert('RGB')
            out = io.BytesIO()
            clean.save(out, format='JPEG', quality=82, exif=b'')
            return base64.b64encode(out.getvalue()).decode('ascii')
    except (OSError, ValueError, binascii.Error, UnidentifiedImageError, Image.DecompressionBombError):
        raise HTTPException(422, 'INVALID_PORTRAIT') from None


def voice_options(owner):
    from .community import PRESETS
    options = {key: (name, os.getenv('COMMUNITY_VOICE_' + key.upper(), ''), True)
               for key, name in PRESETS.items()}
    for entry in json.loads(os.getenv('COMMUNITY_PRIVATE_VOICES') or '{}').get(owner, []):
        if entry['id'].startswith('private-'):
            options[entry['id']] = (entry['name'], entry['provider_id'], False)
    return options


def memories(db, owner, role):
    return [dict(row) for row in db.execute(
        'SELECT id,text FROM role_memories WHERE owner=? AND role=? ORDER BY id', (owner, role))]


def register(app, store, account):
    db = store.db
    db.executescript("""
        CREATE TABLE IF NOT EXISTS role_memories(
            id INTEGER PRIMARY KEY, owner TEXT NOT NULL, role TEXT NOT NULL, text TEXT NOT NULL,
            FOREIGN KEY(owner,role) REFERENCES library(owner,id) ON DELETE CASCADE);
        CREATE INDEX IF NOT EXISTS memories_by_role ON role_memories(owner,role);
        CREATE TABLE IF NOT EXISTS reply_notices(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            owner TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
            comment INTEGER NOT NULL UNIQUE REFERENCES comments(id) ON DELETE CASCADE,
            seen INTEGER NOT NULL DEFAULT 0);
        CREATE INDEX IF NOT EXISTS notices_by_owner ON reply_notices(owner,id);
    """)

    @app.get('/community/characters/{cid}/memories')
    async def list_memories(cid: str, user=Depends(account)):
        store.role(user['id'], cid)
        return {'items': memories(db, user['id'], cid)}

    @app.post('/community/characters/{cid}/memories', status_code=201)
    async def remember(cid: str, data: Memory, user=Depends(account)):
        owner, value = user['id'], data.text.strip()
        store.role(owner, cid)
        if not value:
            raise HTTPException(422, 'INVALID_REQUEST')
        with db:
            if len(memories(db, owner, cid)) >= 20:
                raise HTTPException(409, 'MEMORY_LIMIT')
            mid = db.execute('INSERT INTO role_memories(owner,role,text) VALUES (?,?,?)',
                             (owner, cid, value)).lastrowid
        return {'id': mid, 'text': value}

    @app.put('/community/characters/{cid}/memories/{mid}')
    async def correct(cid: str, mid: int, data: Memory, user=Depends(account)):
        value = data.text.strip()
        if not value:
            raise HTTPException(422, 'INVALID_REQUEST')
        with db:
            if not db.execute('UPDATE role_memories SET text=? WHERE owner=? AND role=? AND id=?',
                              (value, user['id'], cid, mid)).rowcount:
                raise HTTPException(404, 'MEMORY_NOT_FOUND')
        return {'id': mid, 'text': value}

    @app.delete('/community/characters/{cid}/memories/{mid}')
    async def forget(cid: str, mid: int, user=Depends(account)):
        with db:
            if not db.execute('DELETE FROM role_memories WHERE owner=? AND role=? AND id=?',
                              (user['id'], cid, mid)).rowcount:
                raise HTTPException(404, 'MEMORY_NOT_FOUND')
        return {'ok': True}

    @app.put('/community/characters/{cid}/portrait')
    async def portrait(cid: str, data: Portrait, user=Depends(account)):
        store.role(user['id'], cid)
        image = thumbnail(data.image) if data.image else None
        with db:
            db.execute("""UPDATE library SET card=json_patch(card, json_object('portrait', ?))
                WHERE owner=? AND id=?""", (image, user['id'], cid))
        return {'portrait': image}

    @app.post('/community/voices/{vid}/preview')
    async def preview(vid: str, user=Depends(account)):
        options = voice_options(user['id'])
        if vid not in options:
            raise HTTPException(404, 'VOICE_NOT_FOUND')
        store.limit('preview:' + user['id'])
        service = app.state.conversations
        provider_id = options[vid][1]
        if not provider_id and service.settings.mode == 'live':
            raise HTTPException(409, 'PUBLIC_VOICE_NOT_CONFIGURED')
        line = '你好，很高兴见到你。'
        with usage.call(store, service.settings, 'tts') as meter:
            meter.quantity = len(line)
            wav = await service.providers.speech_for_voice(line, provider_id or 'mock')
        return {'audio': base64.b64encode(wav).decode('ascii'), 'mode': service.settings.mode}

    notice_query = """SELECT n.id,n.seen,c.post,c.id AS comment,c.body,c.parent,a.username
        FROM reply_notices n JOIN visible_comments c ON c.id=n.comment AND c.body IS NOT NULL
        JOIN visible_posts p ON p.id=c.post JOIN accounts a ON a.id=c.author WHERE n.owner=?"""

    @app.get('/community/notifications')
    async def notices(before: int | None = None, user=Depends(account)):
        rows = db.execute(notice_query + ' AND (? IS NULL OR n.id<?) ORDER BY n.id DESC LIMIT 30',
                          (user['id'], before, before))
        return {'items': [dict(r) for r in rows]}

    @app.post('/community/notifications/{nid}/open')
    async def open_notice(nid: int, user=Depends(account)):
        with db:
            row = db.execute(notice_query + ' AND n.id=?', (user['id'], nid)).fetchone()
            if not row:
                raise HTTPException(404, 'POST_NOT_FOUND')
            db.execute('UPDATE reply_notices SET seen=1 WHERE id=?', (nid,))
        return dict(row) | {'seen': 1}
