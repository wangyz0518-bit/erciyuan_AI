"""Single-user recording-clone jobs and role bindings, no voice-design inputs."""
import asyncio
import hashlib
import json
import sqlite3
from pathlib import Path
import time
import uuid

from fastapi import Depends, HTTPException, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel, ConfigDict, Field
from starlette.datastructures import UploadFile

from .audio_validation import MAX_UPLOAD, normalize
from .providers import ProviderError, wav
from .voice_enrollment import Enrollment
from .voice_store import VoiceStore


def fingerprint(data):
    return hashlib.sha256(json.dumps(data,sort_keys=True,ensure_ascii=False).encode()).hexdigest()


class RequestId(BaseModel):
    model_config=ConfigDict(extra='forbid')
    request_id:str=Field(pattern=r'^[a-zA-Z0-9_-]{16,100}$')


class PreviewInput(RequestId):
    text:str=Field(min_length=1,max_length=200)


class BindingInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    profile_id:str|None=None
    revision:int=Field(ge=0)


class VoiceProfiles:
    def __init__(self,settings,pool,enrollment=None):
        self.settings,self.pool=settings,pool
        self.store=VoiceStore(settings.data_dir)
        self.enrollment=enrollment or Enrollment(settings)
        self.scope=fingerprint([settings.mode,settings.voice_model,settings.workspace,settings.dashscope_key])
        self.tasks={}
        self.upload_lock=asyncio.Lock()
        self.chat_busy=lambda:False
        self.sweeper=None
        self.store.cleanup()

    async def start(self):
        async def sweep():
            while True:
                await asyncio.sleep(60)
                self.store.cleanup()
        self.sweeper=asyncio.create_task(sweep())

    def owned(self,pid):
        row=self.store.profile(pid)
        if row['scope']!=self.scope: raise ProviderError('VOICE_SCOPE_CHANGED')
        return row

    def ready(self,pid):
        row=self.owned(pid)
        if row['status']!='ready' or not row['provider_id']: raise ProviderError('VOICE_NOT_READY')
        return row

    def selected(self,character,task):
        pid=self.store.binding(character)['profile']
        if not pid:return None
        row=self.ready(pid)
        self.store.snapshot(task,pid,row['provider_id'])
        return row

    def spawn(self,key,coro):
        task=asyncio.create_task(coro)
        self.tasks[key]=task
        def done(t):
            self.tasks.pop(key,None)
            if not t.cancelled():t.exception()
        task.add_done_callback(done)

    def file(self,name):
        root=self.store.directory.resolve()
        path=(root/name).resolve()
        if path.parent!=root:raise ProviderError('INVALID_LOCAL_FILE')
        return path

    def release_reference(self,pid):
        row=self.owned(pid)
        if row['reference']:self.file(row['reference']).unlink(missing_ok=True)
        self.store.update_profile(pid,reference='')

    def public_job(self,jid):
        row=self.store.job(jid)
        p=self.owned(row['profile'])
        out={k:row[k] for k in ('id','kind','status','code','created')}
        out.update(profile_id=p['id'],profile_status=p['status'],
                   audio_url=f'/v1/voice-jobs/{jid}/audio' if row['status']=='complete' and row['audio'] else None)
        if row['kind']=='preview':out['text']=row['text']
        if row['audio'] and not self.file(row['audio']).exists():out.update(audio_url=None,code='PREVIEW_EXPIRED')
        return out

    async def reconcile(self,pid,jid):
        try:
            row=self.owned(pid)
            voice=row['provider_id'] or await self.enrollment.find(row['prefix'])
            if not voice:return
            self.store.update_profile(pid,provider_id=voice)
            status=await self.enrollment.query(voice)
            if status=='OK':
                self.store.update_profile(pid,status='ready',code='')
                self.store.update_job(jid,'complete')
                self.release_reference(pid)
            elif status in ('UNDEPLOYED','FAILED','DELETED'):
                self.store.update_profile(pid,status='failed',code='VOICE_CREATE_REJECTED')
                self.store.update_job(jid,'failed','VOICE_CREATE_REJECTED')
            else:
                self.store.update_profile(pid,status='processing',code='')
        except ProviderError:
            pass # Read-only query can be retried; never submit creation here.

    async def clone(self,pid,jid):
        try:
            row=self.owned(pid)
            voice=await self.enrollment.create(row['prefix'],self.file(row['reference']).read_bytes())
            # Persist the supplier identifier before polling or any other network operation.
            self.store.update_profile(pid,provider_id=voice)
            deadline=time.monotonic()+120
            while time.monotonic()<deadline:
                await self.reconcile(pid,jid)
                if self.owned(pid)['status'] in ('ready','failed'):return
                await asyncio.sleep(2)
            self.store.update_job(jid,'unknown','VOICE_DEPLOYING')
        except asyncio.CancelledError:
            self.store.update_profile(pid,status='unknown',code='SERVER_RESTARTED')
            self.store.update_job(jid,'unknown','SERVER_RESTARTED')
            raise
        except Exception as exc:
            code=exc.code if isinstance(exc,ProviderError) else 'VOICE_RESULT_UNKNOWN'
            definitive=code in ('VOICE_CREATE_REJECTED','VOICE_NOT_CONFIGURED')
            self.store.update_profile(pid,status='failed' if definitive else 'unknown',code=code)
            self.store.update_job(jid,'failed' if definitive else 'unknown',code)

    async def create(self,rid,name,source):
        self.store.cleanup()
        raw_hash=hashlib.sha256(source).hexdigest()
        fp=fingerprint(['clone',self.scope,name,raw_hash])
        old=self.store.replay(rid,fp)
        if old:return self.public_job(old['id'])
        duplicate=self.store.db.execute('SELECT id FROM profiles WHERE scope=? AND fingerprint=?',(self.scope,raw_hash)).fetchone()
        if duplicate:
            p=self.owned(duplicate['id'])
            job=self.store.db.execute("SELECT id FROM voice_jobs WHERE profile=? AND kind='clone' ORDER BY created DESC LIMIT 1",(p['id'],)).fetchone()
            if p['status']=='failed' and (not p['reference'] or not self.file(p['reference']).exists()):
                temp=self.file(uuid.uuid4().hex+'.upload')
                try:
                    temp.write_bytes(source)
                    audio,_=await asyncio.to_thread(normalize,temp)
                    reference=p['id']+'.wav'
                    self.file(reference).write_bytes(audio)
                    self.store.update_profile(p['id'],reference=reference)
                finally:temp.unlink(missing_ok=True)
            self.store.alias(rid,fp,job['id'])
            return self.public_job(job['id']) | {'duplicate':True}
        if len(self.store.profiles(self.scope))>=50:raise ProviderError('VOICE_CATALOG_FULL')
        pid,jid=uuid.uuid4().hex,uuid.uuid4().hex
        temporary=self.file(jid+'.upload')
        try:
            temporary.write_bytes(source)
            audio,metadata=await asyncio.to_thread(normalize,temporary)
        finally:
            temporary.unlink(missing_ok=True)
        reference=jid+'.wav'
        self.file(reference).write_bytes(audio)
        try:
            with self.store.db:
                self.store.db.execute('INSERT INTO profiles VALUES (?,?,?,?,?,?,?,?,?,?,?)',
                    (pid,name,self.scope,raw_hash,'processing','','vc'+jid[:8],reference,json.dumps(metadata),'',time.time()))
                self.store.add_job(jid,rid,fp,'clone',pid)
        except Exception:
            self.file(reference).unlink(missing_ok=True)
            raise
        self.spawn(jid,self.clone(pid,jid))
        return self.public_job(jid)

    async def preview(self,pid,jid,text):
        try:
            row=self.ready(pid)
            self.store.snapshot('preview-'+jid,pid,row['provider_id'])
            data=bytearray()
            async with asyncio.timeout(90):
                generator=self.pool.stream_for_voice(text,row['provider_id'],{})
                try:
                    async for part in generator:
                        data.extend(part)
                        if len(data)>12*1024*1024:raise ProviderError('VOICE_TOO_LARGE')
                finally:await generator.aclose()
            if not data or len(data)%2:raise ProviderError('VOICE_EMPTY')
            path=self.file('preview-'+jid+'.wav')
            path.write_bytes(wav(data))
            self.store.update_job(jid,'complete',audio=path.name)
        except asyncio.CancelledError:
            self.store.update_job(jid,'cancelled','CANCELLED')
            raise
        except Exception as exc:
            self.store.update_job(jid,'failed',exc.code if isinstance(exc,ProviderError) else 'VOICE_PREVIEW_FAILED')

    def make_preview(self,pid,data):
        self.ready(pid)
        if not data.text.strip():raise ProviderError('INVALID_REQUEST')
        fp=fingerprint(['preview',pid,data.text])
        old=self.store.replay(data.request_id,fp)
        if old:return self.public_job(old['id'])
        if self.preview_busy():
            raise ProviderError('VOICE_BUSY')
        jid=uuid.uuid4().hex
        self.store.add_job(jid,data.request_id,fp,'preview',pid,data.text)
        self.spawn(jid,self.preview(pid,jid,data.text))
        return self.public_job(jid)

    def preview_busy(self):
        return self.chat_busy() or self.store.db.execute(
            "SELECT 1 FROM voice_jobs WHERE kind='preview' AND status='running' LIMIT 1").fetchone() is not None

    def retry(self,jid,rid):
        row=self.store.job(jid);p=self.owned(row['profile'])
        fp=fingerprint(['retry',jid])
        old=self.store.replay(rid,fp)
        if old:return self.public_job(old['id'])
        if row['status'] not in ('failed','cancelled'):raise ProviderError('RETRY_NOT_ALLOWED')
        if row['kind']=='clone':
            if p['status']!='failed':raise ProviderError('VOICE_RESULT_UNKNOWN')
            if not p['reference'] or not self.file(p['reference']).exists():raise ProviderError('REUPLOAD_REQUIRED')
            new=uuid.uuid4().hex
            self.store.add_job(new,rid,fp,'clone',p['id'])
            self.store.update_profile(p['id'],status='processing',provider_id='',prefix='vc'+new[:8],code='')
            self.spawn(new,self.clone(p['id'],new))
            return self.public_job(new)
        if self.preview_busy():raise ProviderError('VOICE_BUSY')
        self.ready(p['id'])
        new=uuid.uuid4().hex
        self.store.add_job(new,rid,fp,'preview',p['id'],row['text'])
        self.spawn(new,self.preview(p['id'],new,row['text']))
        return self.public_job(new)

    async def close(self):
        tasks=list(self.tasks.values())+([self.sweeper] if self.sweeper else [])
        for task in tasks:task.cancel()
        await asyncio.gather(*tasks,return_exceptions=True)
        await self.enrollment.close()
        self.store.close()


def register(app,service,auth):
    def checked(call):
        try:return call()
        except ProviderError as exc:
            raise HTTPException(404 if exc.code.endswith('NOT_FOUND') else 409,exc.code) from None
        except sqlite3.Error:
            raise HTTPException(503,'VOICE_SAVE_FAILED') from None

    @app.post('/v1/voice-profiles',dependencies=[Depends(auth)],status_code=202)
    async def create(request:Request):
        if service.settings.mode!='live':raise HTTPException(409,'VOICE_CLONING_REQUIRES_LIVE')
        if service.upload_lock.locked():raise HTTPException(409,'VOICE_BUSY')
        async with service.upload_lock:
            # Enforce the total body cap before the multipart parser can spool a large file.
            body=bytearray()
            async for part in request.stream():
                body.extend(part)
                if len(body)>MAX_UPLOAD+65536:raise HTTPException(413,'AUDIO_SIZE_INVALID')
            async def receive():return {'type':'http.request','body':bytes(body),'more_body':False}
            limited=Request(request.scope,receive)
            async with limited.form(max_files=1,max_fields=4) as form:
                if set(form.keys())!={'request_id','name','consent','file'}:raise HTTPException(422,'INVALID_REQUEST')
                try:rid=RequestId(request_id=form['request_id']).request_id
                except Exception:raise HTTPException(422,'INVALID_REQUEST') from None
                name=form['name']
                if not isinstance(name,str) or not 1<=len(name.strip())<=40 or form['consent']!='true':
                    raise HTTPException(422,'INVALID_REQUEST')
                upload=form['file']
                if not isinstance(upload,UploadFile):raise HTTPException(422,'AUDIO_FORMAT_INVALID')
                source=await upload.read(MAX_UPLOAD+1)
                if not 0<len(source)<=MAX_UPLOAD:raise HTTPException(413,'AUDIO_SIZE_INVALID')
                try:return await service.create(rid,name.strip(),source)
                except ProviderError as exc:
                    raise HTTPException(409 if exc.code in ('REQUEST_ID_CONFLICT','VOICE_BUSY','VOICE_CATALOG_FULL') else 422,exc.code) from None
                except (sqlite3.Error,OSError):
                    raise HTTPException(503,'VOICE_SAVE_FAILED') from None

    @app.get('/v1/voice-profiles',dependencies=[Depends(auth)])
    async def profiles():return {'items':service.store.profiles(service.scope)}

    @app.get('/v1/voice-jobs/{jid}',dependencies=[Depends(auth)])
    async def job(jid:str):
        result=checked(lambda:service.public_job(jid))
        row=service.store.job(jid)
        if row['kind']=='clone' and result['profile_status'] in ('processing','unknown'):
            key='query-'+row['profile']
            if jid not in service.tasks and key not in service.tasks:
                service.spawn(key,service.reconcile(row['profile'],jid))
        return result

    @app.post('/v1/voice-jobs/{jid}/cancel',dependencies=[Depends(auth)])
    async def cancel(jid:str):
        checked(lambda:service.public_job(jid))
        row=service.store.job(jid)
        if row['status'] in ('running','unknown'):
            service.store.update_job(jid,'cancelled','CANCELLED')
            if row['kind']=='preview' and jid in service.tasks:service.tasks[jid].cancel()
            # Keep collecting enrollment result: cancellation cannot undo a supplier creation.
        return service.public_job(jid)

    @app.post('/v1/voice-jobs/{jid}/retry',dependencies=[Depends(auth)],status_code=202)
    async def retry(jid:str,data:RequestId):return checked(lambda:service.retry(jid,data.request_id))

    @app.post('/v1/voice-profiles/{pid}/previews',dependencies=[Depends(auth)],status_code=202)
    async def preview(pid:str,data:PreviewInput):return checked(lambda:service.make_preview(pid,data))

    @app.get('/v1/voice-jobs/{jid}/audio',dependencies=[Depends(auth)])
    async def audio(jid:str):
        checked(lambda:service.public_job(jid));row=service.store.job(jid)
        if row['status']!='complete' or not row['audio']:raise HTTPException(409,'VOICE_NOT_READY')
        path=service.file(row['audio'])
        if not path.exists():raise HTTPException(410,'PREVIEW_EXPIRED')
        return FileResponse(path,media_type='audio/wav',headers={'Cache-Control':'no-store'})

    def binding(character):
        if character not in ('xing','yue'):raise ProviderError('INVALID_CHARACTER')
        row=service.store.binding(character)
        name='默认声音'
        if row['profile']:
            try:name=service.owned(row['profile'])['name']
            except ProviderError:name='声音不可用，请重新选择'
        return {'character_id':character,'profile_id':row['profile'],'revision':row['revision'],'name':name}

    @app.get('/v1/characters/{character}/voice-binding',dependencies=[Depends(auth)])
    async def get_binding(character:str):return checked(lambda:binding(character))

    @app.put('/v1/characters/{character}/voice-binding',dependencies=[Depends(auth)])
    async def set_binding(character:str,data:BindingInput):
        checked(lambda:binding(character))
        if service.chat_busy() or service.pool.lock.locked():raise HTTPException(409,'VOICE_BUSY')
        if data.profile_id:checked(lambda:service.ready(data.profile_id))
        checked(lambda:service.store.bind(character,data.profile_id,data.revision))
        return binding(character)
