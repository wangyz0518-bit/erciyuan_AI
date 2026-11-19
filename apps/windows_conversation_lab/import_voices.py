"""Copy ready voice metadata/bindings into a new lab only; no audio or chat copy."""
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]/'services/model_gateway'))
from gateway.voice_store import VoiceStore


def import_ready(source, target):
    if not source.exists() or (target/'voice_profiles.sqlite').exists():
        return
    target.mkdir(parents=True, exist_ok=True)
    store = VoiceStore(target)
    old = sqlite3.connect(source.resolve().as_uri()+'?mode=ro', uri=True)
    old.row_factory = sqlite3.Row
    try:
        with store.db:
            for row in old.execute("SELECT * FROM profiles WHERE status='ready'"):
                values = dict(row)
                values['reference'] = ''
                cols = list(values)
                store.db.execute('INSERT INTO profiles ('+','.join(cols)+') VALUES ('+','.join('?' for _ in cols)+')', tuple(values.values()))
            for row in old.execute('SELECT * FROM bindings'):
                if not row['profile'] or store.db.execute('SELECT 1 FROM profiles WHERE id=?',(row['profile'],)).fetchone():
                    store.db.execute('INSERT INTO bindings VALUES (?,?,?)',tuple(row))
    finally:
        old.close()
        store.db.close()


if __name__=='__main__':
    import_ready(Path(sys.argv[1]), Path(sys.argv[2]))
