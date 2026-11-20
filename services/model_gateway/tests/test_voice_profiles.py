import asyncio
import io
import json
from pathlib import Path
import struct
import time
import wave

from fastapi.testclient import TestClient
import pytest

from gateway.app import create_app
from gateway.providers import ProviderError, Settings
from gateway.voice_store import VoiceStore

TOKEN='voice-profile-test-token-without-real-key'
HEAD={'Authorization':'Bearer '+TOKEN}


def recording(seconds=10,level=1500,rate=24000):
    out=io.BytesIO()
    with wave.open(out,'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(rate)
        f.writeframes((struct.pack('<hh',level,-level)*(int(seconds*rate)//2)))
    return out.getvalue()


class FakeEnrollment:
    def __init__(self):self.calls=0;self.mode='ok';self.status='OK';self.finds=0
    async def create(self,prefix,audio):
        self.calls+=1
        if self.mode=='wait':await asyncio.sleep(.2)
        if self.mode=='unknown':raise ProviderError('VOICE_RESULT_UNKNOWN')
        if self.mode=='reject':raise ProviderError('VOICE_CREATE_REJECTED')
        return 'fake-voice-'+str(self.calls)
    async def query(self,voice):return self.status
    async def find(self,prefix):self.finds+=1;return 'recovered-voice' if self.mode=='recover' else None
    async def close(self):pass


class FakePool:
    def __init__(self):self.lock=asyncio.Lock();self.voices=[];self.wait=False
    async def stream_for_voice(self,text,voice,metrics):
        self.voices.append(voice)
        yield b'\x01\x03'*2400
        if self.wait:await asyncio.sleep(10)
    async def stream(self,text,role,expression,metrics):
        self.voices.append('default-'+role)
        yield b'\x01\x03'*2400
    async def close(self):pass


class FakeChat:
    async def reply(self,role,history,content):yield '完整回复'


def setup(tmp_path, enrollment=None,pool=None):
    enroll=enrollment or FakeEnrollment();pool=pool or FakePool()
    settings=Settings(mode='live',token=TOKEN,data_dir=str(tmp_path),dashscope_key='fake-key',voice='default')
    app=create_app(settings,FakeChat(),pool,enrollment=enroll)
    return app,enroll,pool


def upload(client,rid='recording-request-0001',data=None,name='测试声音'):
    return client.post('/v1/voice-profiles',headers=HEAD,
        data={'request_id':rid,'name':name,'consent':'true'},
        files={'file':('test.wav',recording() if data is None else data,'audio/wav')})


def wait(client,jid,status='complete'):
    for _ in range(100):
        row=client.get('/v1/voice-jobs/'+jid,headers=HEAD).json()
        if row['status']==status:return row
        time.sleep(.02)
    raise AssertionError(row)


def test_upload_idempotence_preview_binding_and_restart(tmp_path):
    app,enroll,pool=setup(tmp_path)
    with TestClient(app) as c:
        assert c.get('/v1/voice-profiles').status_code==401
        job=upload(c).json();wait(c,job['id']);pid=job['profile_id']
        assert upload(c).json()['id']==job['id']
        assert upload(c,rid='duplicate-content-0001').json()['id']==job['id']
        assert upload(c,rid='duplicate-content-0001',name='其他名字').status_code==409
        assert upload(c,name='改名').status_code==409
        assert enroll.calls==1
        assert not list((tmp_path/'voice-files').glob('*.upload'))
        assert app.state.voice_profiles.owned(pid)['reference']==''
        p=c.post(f'/v1/voice-profiles/{pid}/previews',headers=HEAD,json={'request_id':'preview-request-0001','text':'你好'}).json()
        wait(c,p['id']);audio=c.get(p['audio_url'] or '/v1/voice-jobs/'+p['id']+'/audio',headers=HEAD)
        assert audio.status_code==200 and audio.content[:4]==b'RIFF'
        result=c.put('/v1/characters/xing/voice-binding',headers=HEAD,json={'profile_id':pid,'revision':0})
        assert result.json()['revision']==1
        assert c.put('/v1/characters/xing/voice-binding',headers=HEAD,json={'profile_id':None,'revision':0}).status_code==409
        assert c.get('/v1/characters/yue/voice-binding',headers=HEAD).json()['profile_id'] is None
    app2,_,_=setup(tmp_path)
    with TestClient(app2) as c:
        assert c.get('/v1/characters/xing/voice-binding',headers=HEAD).json()['profile_id']==pid
        assert len(c.get('/v1/voice-profiles',headers=HEAD).json()['items'])==1


@pytest.mark.parametrize('data,code',[(b'','AUDIO_SIZE_INVALID'),(b'broken','AUDIO_FORMAT_INVALID'),
    (recording(1),'AUDIO_DURATION_INVALID'),(recording(31),'AUDIO_DURATION_INVALID'),
    (recording(level=0),'AUDIO_SILENT'),(recording(rate=8000),'AUDIO_SAMPLE_RATE_LOW')],
    ids=['empty','broken','short','long','silent','sample-rate'])
def test_bad_audio_never_calls_supplier(tmp_path,data,code):
    app,enroll,_=setup(tmp_path)
    with TestClient(app) as c:
        r=upload(c,data=data)
        assert r.status_code in (413,422) and r.json()['error']['code']==code
        assert enroll.calls==0
        assert c.get('/v1/voice-profiles',headers=HEAD).json()['items']==[]
        assert list((tmp_path/'voice-files').iterdir())==[]


def test_unknown_creation_queries_without_resubmitting(tmp_path):
    app,enroll,_=setup(tmp_path);enroll.mode='unknown'
    with TestClient(app) as c:
        job=upload(c).json();wait(c,job['id'],'unknown')
        assert c.post('/v1/voice-jobs/'+job['id']+'/retry',headers=HEAD,json={'request_id':'unknown-retry-0001'}).status_code==409
        enroll.mode='recover'
        wait(c,job['id'])
        assert enroll.calls==1 and enroll.finds>0


def test_failed_creation_explicit_retry_and_reference_expiry(tmp_path):
    app,enroll,_=setup(tmp_path);enroll.mode='reject'
    with TestClient(app) as c:
        job=upload(c).json();wait(c,job['id'],'failed')
        profile=app.state.voice_profiles.owned(job['profile_id'])
        (tmp_path/'voice-files'/profile['reference']).unlink()
        assert c.post('/v1/voice-jobs/'+job['id']+'/retry',headers=HEAD,json={'request_id':'failed-retry-0001'}).json()['error']['code']=='REUPLOAD_REQUIRED'
        assert upload(c,rid='restore-reference-0001').json()['id']==job['id']
        enroll.mode='ok'
        new=c.post('/v1/voice-jobs/'+job['id']+'/retry',headers=HEAD,json={'request_id':'failed-retry-0001'}).json()
        wait(c,new['id'])
        assert c.post('/v1/voice-jobs/'+job['id']+'/retry',headers=HEAD,json={'request_id':'failed-retry-0001'}).json()['id']==new['id']
        assert enroll.calls==2


def test_cancel_creation_keeps_late_result_without_binding(tmp_path):
    app,enroll,_=setup(tmp_path);enroll.mode='wait'
    with TestClient(app) as c:
        job=upload(c).json()
        assert c.post('/v1/voice-jobs/'+job['id']+'/cancel',headers=HEAD).json()['status']=='cancelled'
        for _ in range(100):
            r=c.get('/v1/voice-jobs/'+job['id'],headers=HEAD).json()
            if r['profile_status']=='ready':break
            time.sleep(.02)
        assert r['status']=='cancelled' and r['profile_status']=='ready'
        assert c.get('/v1/characters/xing/voice-binding',headers=HEAD).json()['profile_id'] is None
        assert enroll.calls==1


def test_role_selection_stream_and_old_cache_stays_old(tmp_path):
    app,enroll,pool=setup(tmp_path)
    with TestClient(app) as c:
        job=upload(c).json();wait(c,job['id']);pid=job['profile_id']
        c.put('/v1/characters/xing/voice-binding',headers=HEAD,json={'profile_id':pid,'revision':0})
        with c.websocket_connect('/v2/conversations/local-xing/stream',headers=HEAD) as ws:
            ws.receive_json()
            ws.send_json({'command':'chat.send','request_id':'voice-chat-request-01','character_id':'xing','content':'你好'})
            while True:
                packet=ws.receive()
                if packet.get('text'):
                    row=json.loads(packet['text'])
                    if row['event']=='audio.completed':sid=row['speech_id'];break
            assert pool.voices[-1]=='fake-voice-1'
            # Wait for the finished task callback, then restore default.
            for _ in range(100):
                r=c.put('/v1/characters/xing/voice-binding',headers=HEAD,json={'profile_id':None,'revision':1})
                if r.status_code==200:break
                time.sleep(.01)
            assert r.status_code==200
            before=len(pool.voices)
            ws.send_json({'command':'speech.retry','request_id':'voice-chat-request-01','speech_id':sid})
            while True:
                packet=ws.receive()
                if packet.get('text') and json.loads(packet['text'])['event']=='audio.completed':break
            assert len(pool.voices)==before
        assert app.state.voice_profiles.store.db.execute('SELECT profile FROM selections WHERE task=?',(sid,)).fetchone()[0]==pid


def test_restart_unknown_and_scope_isolation(tmp_path):
    store=VoiceStore(tmp_path)
    with store.db:
        store.db.execute('INSERT INTO profiles VALUES (?,?,?,?,?,?,?,?,?,?,?)',('p','声音','old-scope','hash','processing','','pfx','','{}','',time.time()))
        store.add_job('j','original-request-id','fp','clone','p')
    store.close()
    app,_,_=setup(tmp_path)
    with TestClient(app) as c:
        assert app.state.voice_profiles.store.profile('p')['status']=='unknown'
        assert c.get('/v1/voice-profiles',headers=HEAD).json()['items']==[]
        assert c.get('/v1/voice-jobs/j',headers=HEAD).status_code==409


def test_binding_write_failure_keeps_previous_choice(tmp_path):
    app,_,_=setup(tmp_path)
    with TestClient(app) as c:
        job=upload(c).json();wait(c,job['id']);pid=job['profile_id']
        assert c.put('/v1/characters/xing/voice-binding',headers=HEAD,json={'profile_id':pid,'revision':0}).status_code==200
        db=app.state.voice_profiles.store.db
        db.execute("CREATE TRIGGER fail_binding BEFORE INSERT ON bindings BEGIN SELECT RAISE(ABORT,'test storage failure'); END")
        result=c.put('/v1/characters/xing/voice-binding',headers=HEAD,json={'profile_id':None,'revision':1})
        assert result.status_code==503 and result.json()['error']['code']=='VOICE_SAVE_FAILED'
        assert c.get('/v1/characters/xing/voice-binding',headers=HEAD).json()['profile_id']==pid


def test_preview_cancel_retry_and_busy_rejection(tmp_path):
    app,_,pool=setup(tmp_path)
    with TestClient(app) as c:
        job=upload(c).json();wait(c,job['id']);pid=job['profile_id']
        pool.wait=True
        p=c.post(f'/v1/voice-profiles/{pid}/previews',headers=HEAD,json={'request_id':'preview-cancel-001','text':'取消试听'}).json()
        assert c.post('/v1/voice-jobs/'+p['id']+'/cancel',headers=HEAD).json()['status']=='cancelled'
        time.sleep(.05)
        pool.wait=False
        retry=c.post('/v1/voice-jobs/'+p['id']+'/retry',headers=HEAD,json={'request_id':'preview-retry-001'}).json()
        assert retry['text']=='取消试听'
        wait(c,retry['id'])
        assert c.get('/v1/voice-jobs/'+retry['id']+'/audio',headers=HEAD).content.startswith(b'RIFF')


@pytest.mark.parametrize('extension,codec',[('mp3','libmp3lame'),('m4a','aac')])
def test_compressed_formats_decode_before_enrollment(tmp_path,extension,codec):
    import imageio_ffmpeg
    import math
    import subprocess
    source=tmp_path/'source.wav'
    with wave.open(str(source),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(24000)
        f.writeframes(b''.join(struct.pack('<h',int(4000*math.sin(2*math.pi*500*i/24000))) for i in range(11*24000)))
    dest=tmp_path/('sample.'+extension)
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(),'-v','error','-i',str(source),'-c:a',codec,str(dest)],check=True,capture_output=True)
    app,enroll,_=setup(tmp_path)
    with TestClient(app) as c:
        result=upload(c,data=dest.read_bytes())
        assert result.status_code==202,result.json()
        job=result.json();wait(c,job['id'])
        assert enroll.calls==1
