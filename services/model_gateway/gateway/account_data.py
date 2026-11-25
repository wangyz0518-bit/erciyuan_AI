"""Recovery, device snapshots and account erasure for the community service."""
import asyncio
import hmac
import json
import os
import secrets
import time

from fastapi import Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field, SecretStr

from .community import password_hash, token_hash


class Password(BaseModel):
    password: SecretStr = Field(min_length=8, max_length=128)


class Reset(Password):
    username: str = Field(min_length=2, max_length=32)
    code: SecretStr = Field(min_length=20, max_length=128)


TABLES = ('characters', 'character_timelines', 'raw_events', 'generation_tasks',
          'archive_segments', 'archive_cursors', 'memory_summaries', 'memory_terms',
          'summary_sources', 'persona_identity_versions', 'identity_candidates')
MAX_BACKUP = 8 * 1024 * 1024


def register(app, store, account):
    db = store.db
    conversations = app.state.conversations
    path = conversations.store.db.execute('PRAGMA database_list').fetchone()['file']
    db.execute('ATTACH DATABASE ? AS chat_history', (path,))
    db.executescript("""
        CREATE TABLE IF NOT EXISTS recovery_codes(
            owner TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE, digest TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS device_backups(
            owner TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
            data TEXT NOT NULL, created INTEGER NOT NULL);
    """)

    async def verify(owner, password):
        store.limit('password:' + owner)
        row = db.execute('SELECT salt,digest FROM accounts WHERE id=?', (owner,)).fetchone()
        if not row:
            raise HTTPException(401, 'INVALID_CREDENTIALS')
        hashed = await asyncio.to_thread(password_hash, password.get_secret_value(), row['salt'])
        if not hmac.compare_digest(hashed, row['digest']):
            raise HTTPException(401, 'INVALID_CREDENTIALS')
        # Password may have changed while scrypt was running.
        if not db.execute('SELECT 1 FROM accounts WHERE id=? AND digest=?', (owner, hashed)).fetchone():
            raise HTTPException(401, 'INVALID_CREDENTIALS')

    async def disconnect(owner):
        session = conversations.sessions.get(owner)
        if session and not store.user(session.token):
            await conversations.revoke(session.token)

    @app.post('/community/account/recovery-code')
    async def issue(data: Password, response: Response, user=Depends(account)):
        await verify(user['id'], data.password)
        code = secrets.token_urlsafe(24)
        with db:
            db.execute('INSERT OR REPLACE INTO recovery_codes VALUES (?,?)', (user['id'], token_hash(code)))
        response.headers['Cache-Control'] = 'no-store'
        return {'code': code}

    @app.post('/community/account/reset')
    async def reset(data: Reset, request: Request):
        store.limit('recovery:' + request.client.host)
        row = db.execute('''SELECT a.id,r.digest FROM accounts a JOIN recovery_codes r ON a.id=r.owner
            WHERE a.login=?''', (data.username.strip().casefold(),)).fetchone()
        digest = token_hash(data.code.get_secret_value())
        if not row or not hmac.compare_digest(row['digest'], digest):
            raise HTTPException(401, 'INVALID_RECOVERY')
        owner, salt = row['id'], os.urandom(16)
        password = await asyncio.to_thread(password_hash, data.password.get_secret_value(), salt)
        with db:
            if not db.execute('DELETE FROM recovery_codes WHERE owner=? AND digest=?', (owner, digest)).rowcount:
                raise HTTPException(401, 'INVALID_RECOVERY')
            db.execute('UPDATE accounts SET digest=?,salt=? WHERE id=?', (password, salt, owner))
            db.execute('DELETE FROM sessions WHERE owner=?', (owner,))
        await disconnect(owner)
        return {'ok': True}

    @app.put('/community/account/backup')
    async def backup(request: Request, user=Depends(account)):
        raw = bytearray()
        async for part in request.stream():
            if len(raw) + len(part) > MAX_BACKUP:
                raise HTTPException(413, 'BACKUP_TOO_LARGE')
            raw.extend(part)
        try:
            document = raw.decode('utf-8')
            data = json.loads(document)
            if (not isinstance(data, dict) or data.get('format') != 'erciyuan-person-memory-export'
                    or data.get('schema_version') != 1 or data.get('owner_id') != user['id']
                    or data.get('attachments') != []):
                raise ValueError()
            for table in TABLES:
                if not isinstance(data.get(table), list) or any(
                    not isinstance(r, dict) or r.get('owner_id') != user['id'] for r in data[table]
                ):
                    raise ValueError()
        except (ValueError, RecursionError, UnicodeError):
            raise HTTPException(422, 'INVALID_BACKUP') from None
        created = int(time.time())
        with db:
            db.execute('INSERT OR REPLACE INTO device_backups VALUES (?,?,?)',
                       (user['id'], document, created))
        return {'created': created}

    @app.get('/community/account/backup')
    async def get_backup(response: Response, user=Depends(account)):
        row = db.execute('SELECT data,created FROM device_backups WHERE owner=?', (user['id'],)).fetchone()
        if not row:
            raise HTTPException(404, 'NO_BACKUP')
        response.headers['Cache-Control'] = 'no-store'
        return {'snapshot': json.loads(row['data']), 'created': row['created']}

    @app.delete('/community/account')
    async def erase(data: Password, user=Depends(account)):
        owner = user['id']
        await verify(owner, data.password)
        with db:
            db.execute('DELETE FROM sessions WHERE owner=?', (owner,))
            db.execute('DELETE FROM support_tickets WHERE reporter=?', (owner,))
            db.execute('UPDATE support_tickets SET handler=NULL WHERE handler=?', (owner,))
            for kind, table in (('post', 'posts'), ('comment', 'comments')):
                db.execute(f'''UPDATE support_tickets SET evidence=NULL WHERE kind=? AND target IN
                    (SELECT id FROM {table} WHERE author=?)''', (kind, owner))
            db.execute('DELETE FROM posts WHERE author=?', (owner,))
            db.execute('DELETE FROM comments WHERE author=?', (owner,))
            db.execute('DELETE FROM library WHERE owner=?', (owner,))
            db.execute('DELETE FROM chat_history.conversation_turns WHERE owner=?', (owner,))
            db.execute('DELETE FROM accounts WHERE id=?', (owner,))
        await disconnect(owner)
        return {'ok': True}
