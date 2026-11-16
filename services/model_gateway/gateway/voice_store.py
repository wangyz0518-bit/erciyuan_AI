"""Persistent local-user voice catalog, separate from all chat databases."""
import json
from pathlib import Path
import sqlite3
import time

from .providers import ProviderError


class VoiceStore:
    def __init__(self, directory):
        self.directory=Path(directory)/'voice-files'
        self.directory.mkdir(parents=True,exist_ok=True)
        self.db=sqlite3.connect(str(Path(directory)/'voice_profiles.sqlite'),check_same_thread=False)
        self.db.row_factory=sqlite3.Row
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS profiles (
          id TEXT PRIMARY KEY, name TEXT, scope TEXT, fingerprint TEXT, status TEXT,
          provider_id TEXT, prefix TEXT UNIQUE, reference TEXT, metadata TEXT, code TEXT, created REAL,
          UNIQUE(scope,fingerprint));
        CREATE TABLE IF NOT EXISTS voice_jobs (
          id TEXT PRIMARY KEY, request_id TEXT UNIQUE, fingerprint TEXT, kind TEXT, profile TEXT,
          status TEXT, code TEXT, text TEXT, audio TEXT, created REAL);
        CREATE TABLE IF NOT EXISTS bindings (character TEXT PRIMARY KEY, profile TEXT, revision INTEGER);
        CREATE TABLE IF NOT EXISTS aliases (request_id TEXT PRIMARY KEY, fingerprint TEXT, job TEXT);
        CREATE TABLE IF NOT EXISTS selections (task TEXT PRIMARY KEY, profile TEXT, provider_id TEXT, created REAL);
        ''')
        with self.db:
            self.db.execute("UPDATE profiles SET status='unknown',code='SERVER_RESTARTED' WHERE status='processing'")
            self.db.execute("UPDATE voice_jobs SET status=CASE WHEN kind='clone' THEN 'unknown' ELSE 'failed' END,code='SERVER_RESTARTED' WHERE status='running'")

    def profile(self,pid):
        row=self.db.execute('SELECT * FROM profiles WHERE id=?',(pid,)).fetchone()
        if not row: raise ProviderError('VOICE_PROFILE_NOT_FOUND')
        return dict(row)

    def job(self,jid):
        row=self.db.execute('SELECT * FROM voice_jobs WHERE id=?',(jid,)).fetchone()
        if not row: raise ProviderError('VOICE_JOB_NOT_FOUND')
        return dict(row)

    def replay(self,rid,fingerprint):
        row=self.db.execute('SELECT * FROM voice_jobs WHERE request_id=?',(rid,)).fetchone()
        if not row:
            alias=self.db.execute('SELECT * FROM aliases WHERE request_id=?',(rid,)).fetchone()
            if alias:
                if alias['fingerprint']!=fingerprint:raise ProviderError('REQUEST_ID_CONFLICT')
                return self.job(alias['job'])
        if row and row['fingerprint']!=fingerprint: raise ProviderError('REQUEST_ID_CONFLICT')
        return dict(row) if row else None

    def alias(self,rid,fp,jid):
        if self.db.execute('SELECT count(*) FROM aliases').fetchone()[0]>=1000:raise ProviderError('VOICE_CATALOG_FULL')
        with self.db:self.db.execute('INSERT INTO aliases VALUES (?,?,?)',(rid,fp,jid))

    def add_job(self,jid,rid,fingerprint,kind,pid,text=''):
        if self.db.execute('SELECT count(*) FROM voice_jobs').fetchone()[0]>=1000:
            raise ProviderError('VOICE_CATALOG_FULL')
        with self.db:
            self.db.execute('INSERT INTO voice_jobs VALUES (?,?,?,?,?,?,?,?,?,?)',
                            (jid,rid,fingerprint,kind,pid,'running','',text,'',time.time()))

    def update_job(self,jid,status,code='',audio=''):
        with self.db:
            self.db.execute("UPDATE voice_jobs SET status=?,code=?,audio=? WHERE id=? AND status!='cancelled'",
                            (status,code,audio,jid))

    def update_profile(self,pid,**fields):
        allowed={'status','provider_id','prefix','reference','code'}
        if not fields or not set(fields)<=allowed: raise ValueError('INVALID_PROFILE_UPDATE')
        with self.db:
            self.db.execute('UPDATE profiles SET '+','.join(k+'=?' for k in fields)+' WHERE id=?',
                            (*fields.values(),pid))

    @staticmethod
    def public_profile(row):
        return {k:row[k] for k in ('id','name','status','code','created')} | {'audio':json.loads(row['metadata'])}

    def profiles(self,scope):
        result=[]
        for row in self.db.execute('SELECT * FROM profiles WHERE scope=? ORDER BY created DESC',(scope,)):
            p=self.public_profile(dict(row))
            last=self.db.execute('SELECT id FROM voice_jobs WHERE profile=? ORDER BY created DESC LIMIT 1',(row['id'],)).fetchone()
            p['last_job_id']=last['id'] if last else None
            result.append(p)
        return result

    def binding(self,character):
        row=self.db.execute('SELECT * FROM bindings WHERE character=?',(character,)).fetchone()
        return dict(row) if row else {'character':character,'profile':None,'revision':0}

    def bind(self,character,pid,revision):
        with self.db:
            if self.binding(character)['revision']!=revision: raise ProviderError('BINDING_CHANGED')
            self.db.execute('INSERT OR REPLACE INTO bindings VALUES (?,?,?)',(character,pid,revision+1))
        return self.binding(character)

    def snapshot(self,task,pid,provider_id):
        with self.db:
            self.db.execute('INSERT OR IGNORE INTO selections VALUES (?,?,?,?)',(task,pid,provider_id,time.time()))
            self.db.execute('DELETE FROM selections WHERE created<?',(time.time()-86400,))

    def cleanup(self):
        # Only files generated by this service inside its own resolved directory.
        root=self.directory.resolve()
        for path in root.iterdir():
            if path.suffix not in ('.upload','.wav') or not path.is_file():continue
            if path.resolve().parent!=root:continue
            if time.time()-path.stat().st_mtime>86400: path.unlink(missing_ok=True)

    def close(self): self.db.close()
