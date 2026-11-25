"""V3 local history, separate from legacy ledgers and mobile databases."""
import hashlib
import sqlite3
import time
from pathlib import Path

from .providers import ProviderError


RECENT_TURNS = '''
    FROM conversation_turns
    WHERE owner = ? AND character = ?
    ORDER BY rowid DESC LIMIT 100
'''


class ConversationStore:
    def __init__(self, directory):
        Path(directory).mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(Path(directory)/'conversations-v3.sqlite'), check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.owner = ''  # Existing development-only rows retain this scope.
        columns = {r['name'] for r in self.db.execute('PRAGMA table_info(conversation_turns)')}
        self.db.execute('BEGIN IMMEDIATE')
        if columns and 'owner' not in columns:
            self.db.execute('ALTER TABLE conversation_turns RENAME TO legacy_turns')
        self.db.execute('''CREATE TABLE IF NOT EXISTS conversation_turns (
            owner TEXT NOT NULL, id TEXT NOT NULL, character TEXT NOT NULL, kind TEXT NOT NULL,
            prompt TEXT NOT NULL, reply TEXT NOT NULL DEFAULT '',
            state TEXT NOT NULL, audio_state TEXT NOT NULL DEFAULT 'waiting',
            played_frames INTEGER NOT NULL DEFAULT 0, total_frames INTEGER NOT NULL DEFAULT 0,
            recording BLOB, fingerprint TEXT NOT NULL, code TEXT NOT NULL DEFAULT '', created REAL NOT NULL,
            PRIMARY KEY(owner,id))''')
        if columns and 'owner' not in columns:
            self.db.execute("INSERT INTO conversation_turns SELECT '', * FROM legacy_turns ORDER BY rowid")
            self.db.execute('DROP TABLE legacy_turns')
        self.db.execute('CREATE INDEX IF NOT EXISTS turns_by_character ON conversation_turns(owner, character)')
        self.db.execute("""CREATE INDEX IF NOT EXISTS account_turn_usage ON conversation_turns(created,kind)
            WHERE owner<>''""")
        with self.db:
            self.db.execute("UPDATE conversation_turns SET state='interrupted',code='SERVER_RESTARTED' WHERE state='running'")
            self.db.execute("UPDATE conversation_turns SET audio_state='interrupted' WHERE audio_state IN ('waiting','streaming','awaiting_playback')")

    def scoped(self, owner):
        view = object.__new__(ConversationStore)
        view.db, view.owner = self.db, owner
        return view

    def get(self, rid):
        row = self.db.execute('SELECT * FROM conversation_turns WHERE owner=? AND id=?', (self.owner, rid)).fetchone()
        return dict(row) if row else None

    def begin(self, rid, character, kind, prompt, recording=None, speak=True):
        fingerprint = hashlib.sha256((character+'\0'+kind+'\0'+str(speak)+'\0'+prompt).encode()+(recording or b'')).hexdigest()
        old = self.get(rid)
        if old:
            if old['fingerprint'] != fingerprint:
                raise ProviderError('REQUEST_ID_CONFLICT')
            return False
        size = self.db.execute('SELECT count(*),coalesce(sum(length(recording)),0) FROM conversation_turns WHERE owner=?', (self.owner,)).fetchone()
        if size[0] >= 2000 or size[1]+len(recording or b'') > 128*1024*1024:
            raise ProviderError('HISTORY_CAPACITY_REACHED')
        with self.db:
            self.db.execute('INSERT INTO conversation_turns (owner,id,character,kind,prompt,state,recording,fingerprint,created) VALUES (?,?,?,?,?,?,?,?,?)',
                            (self.owner, rid, character, kind, prompt, 'running', recording, fingerprint, time.time()))
        return True

    def update(self, rid, **fields):
        if not fields or not fields.keys() <= {'reply','state','audio_state','total_frames','code'}:
            raise ValueError('Invalid history update')
        with self.db:
            self.db.execute('UPDATE conversation_turns SET '+','.join(k+'=?' for k in fields)+' WHERE owner=? AND id=?', (*fields.values(), self.owner, rid))

    def progress(self, rid, frames, complete=False):
        row = self.get(rid)
        if not row or type(frames) is not int or not 0 <= frames <= row['total_frames']:
            raise ProviderError('INVALID_PLAYBACK_PROGRESS')
        if complete and (row['audio_state'] != 'awaiting_playback' or not frames or frames != row['total_frames']):
            raise ProviderError('INCOMPLETE_PLAYBACK')
        with self.db:
            self.db.execute('UPDATE conversation_turns SET played_frames=max(played_frames,?) WHERE owner=? AND id=?', (frames, self.owner, rid))
            if complete:
                self.db.execute("UPDATE conversation_turns SET audio_state='played' WHERE owner=? AND id=?", (self.owner, rid))

    @staticmethod
    def public(row):
        return {k:v for k,v in row.items() if k not in ('recording','fingerprint','owner')} | {'has_recording': bool(row['recording'])}

    def rows(self, character):
        cursor = self.db.execute('''
            SELECT id, character, kind, prompt, reply, state, audio_state,
                   played_frames, total_frames, code, created,
                   coalesce(length(recording), 0) > 0 AS has_recording
        ''' + RECENT_TURNS, (self.owner, character))
        rows = []
        for row in cursor:
            item = dict(row)
            item['has_recording'] = bool(item['has_recording'])
            rows.append(item)
        rows.reverse()
        return rows

    def history(self, character):
        cursor = self.db.execute(
            'SELECT kind, prompt, reply, state, audio_state ' + RECENT_TURNS,
            (self.owner, character),
        )
        result, size = [], 0
        for row in cursor:
            if row['state'] == 'running':
                continue
            prompt, reply = row['prompt'], row['reply']
            # Conservative until provider word alignment is implemented: do not
            # claim the user heard the unplayed remainder of an interrupted call.
            if row['kind'] == 'call' and row['audio_state'] != 'played':
                reply = '（上轮语音未确认播放完毕或已被打断，请根据用户的新话继续，不假设用户听过未播内容。）'
            elif row['state'] != 'complete':
                reply = '（上轮回复未完成。）'
            if size+len(prompt)+len(reply) > 24000 or len(result) >= 20:
                break
            result[0:0] = [{'role':'user','content':prompt}, {'role':'assistant','content':reply}]
            size += len(prompt)+len(reply)
        return result

    def daily_account_usage(self, since, until):
        rows = self.db.execute("""SELECT date(created,'unixepoch') AS day, count(*) AS total,
            sum(kind='text') AS text, sum(kind IN ('hold','call')) AS voice
            FROM conversation_turns WHERE owner<>'' AND created BETWEEN ? AND ?
            GROUP BY day ORDER BY day""", (since, until))
        return [dict(row) for row in rows]

    def close(self):
        self.db.close()
