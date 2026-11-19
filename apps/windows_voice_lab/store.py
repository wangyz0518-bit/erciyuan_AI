"""Desktop-only history; never opens or migrates the phone database."""
import sqlite3
from pathlib import Path


class Store:
    def __init__(self, path):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute('''CREATE TABLE IF NOT EXISTS turns (
            id INTEGER PRIMARY KEY, request_id TEXT UNIQUE, role TEXT,
            prompt TEXT, reply TEXT, text_state TEXT, audio_state TEXT)''')
        self.db.execute("UPDATE turns SET text_state='interrupted' WHERE text_state='running'")
        self.db.execute("UPDATE turns SET audio_state='interrupted' WHERE audio_state='running'")
        self.db.commit()

    def rows(self, role):
        rows = self.db.execute('SELECT * FROM turns WHERE role=? ORDER BY id DESC LIMIT 40', (role,)).fetchall()
        return [dict(row) for row in reversed(rows)]

    def last(self, role):
        rows = self.rows(role)
        return rows[-1] if rows else None

    def begin(self, rid, role, prompt, retry=None):
        with self.db:
            if retry is None:
                cursor = self.db.execute('INSERT INTO turns VALUES (NULL,?,?,?,?,?,?)',
                                         (rid, role, prompt, '', 'running', 'waiting'))
                return cursor.lastrowid
            self.db.execute("UPDATE turns SET request_id=?,reply='',text_state='running',audio_state='waiting' WHERE id=? AND role=?",
                            (rid, retry, role))
            return retry

    def text(self, row, content, state):
        with self.db:
            self.db.execute('UPDATE turns SET reply=?,text_state=? WHERE id=?', (content, state, row))

    def audio(self, row, state):
        with self.db:
            self.db.execute('UPDATE turns SET audio_state=? WHERE id=?', (state, row))

    def history(self, role, before=None):
        result, count = [], 0
        for row in reversed(self.rows(role)):
            if row['text_state'] != 'complete' or (before is not None and row['id'] >= before):
                continue
            size = len(row['prompt']) + len(row['reply'])
            if len(result) >= 20 or count + size > 24000:
                break
            result[0:0] = [{'role': 'user', 'content': row['prompt']},
                           {'role': 'assistant', 'content': row['reply']}]
            count += size
        return result

    def close(self):
        self.db.close()
