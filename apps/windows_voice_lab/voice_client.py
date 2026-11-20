"""Gateway-only voice management and output-only local preview."""
import asyncio
import io
from pathlib import Path
import subprocess
import sys
import wave

import httpx
import imageio_ffmpeg

from player import Player

LABELS={
    'VOICE_SAVE_FAILED':'声音资料保存失败，请检查磁盘空间；原有角色选择保留。',
    'AUDIO_SIZE_INVALID':'文件不能为空，且不能超过 10 MB。',
    'AUDIO_FORMAT_INVALID':'请选择有效的 WAV、MP3 或 M4A 录音。',
    'AUDIO_DECODE_FAILED':'录音无法读取，请检查文件是否损坏。',
    'AUDIO_DURATION_INVALID':'请使用 10–30 秒的录音。',
    'AUDIO_SAMPLE_RATE_LOW':'录音采样率需至少 16 kHz。',
    'AUDIO_SILENT':'录音接近静音，请换一段清晰语音。',
    'VOICE_CREATE_REJECTED':'声音服务拒绝了这段录音，请检查录音后重试。',
    'VOICE_RESULT_UNKNOWN':'创建结果待核实，请刷新状态，不要重复创建。',
    'VOICE_DEPLOYING':'音色仍在云端处理中，可稍后刷新状态。',
    'REUPLOAD_REQUIRED':'临时录音已清理，请重新选择并上传原录音。',
    'VOICE_NOT_READY':'音色还不能使用，请先刷新创建状态。',
    'VOICE_BUSY':'声音或聊天任务正在进行，请停止或稍后再试。',
    'BINDING_CHANGED':'声音选择已变化，请刷新列表后再应用。',
    'VOICE_SCOPE_CHANGED':'当前服务配置与此音色不匹配，请重新选择。',
    'PREVIEW_EXPIRED':'试听音频已过期，请重新生成试听。',
    'VOICE_PREVIEW_FAILED':'试听生成失败，可明确点击重试。',
    'REQUEST_ID_CONFLICT':'请求内容发生变化，请刷新后重新操作。',
    'RETRY_NOT_ALLOWED':'当前状态不能重试，请先查询原任务。',
    'NETWORK_UNCERTAIN':'连接未完成。请刷新列表核实结果，系统没有自动重复提交。',
}


class VoiceError(Exception):
    def __init__(self,code):
        self.code=code
        super().__init__(LABELS.get(code,'操作未完成（'+code+'），请刷新状态。'))


def local_pcm(path):
    path=Path(path)
    if path.suffix.lower() not in ('.wav','.mp3','.m4a'):raise VoiceError('AUDIO_FORMAT_INVALID')
    if not 0<path.stat().st_size<=10*1024*1024:raise VoiceError('AUDIO_SIZE_INVALID')
    fmt={'.wav':'wav','.mp3':'mp3','.m4a':'mov'}[path.suffix.lower()]
    try:
        p=subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(),'-nostdin','-v','error',
            '-protocol_whitelist','file,pipe','-f',fmt,'-i',str(path.resolve()),'-map','0:a:0','-vn','-t','31',
            '-af','pan=mono|c0=c0','-ar','24000','-ac','1','-f','s16le','pipe:1'],
            capture_output=True,timeout=20,creationflags=subprocess.CREATE_NO_WINDOW if sys.platform=='win32' else 0)
    except Exception:raise VoiceError('AUDIO_DECODE_FAILED') from None
    if p.returncode or len(p.stdout)%2:raise VoiceError('AUDIO_DECODE_FAILED')
    if not 10<=len(p.stdout)/48000<=30:raise VoiceError('AUDIO_DURATION_INVALID')
    return p.stdout


class VoiceClient:
    def __init__(self,url,token):
        self.http=httpx.AsyncClient(base_url=url,headers={'Authorization':'Bearer '+token},
            timeout=httpx.Timeout(40,connect=5),trust_env=False)
        self.play_task=None
        self.player=None

    async def request(self,method,path,**kwargs):
        try:
            response=await self.http.request(method,path,**kwargs)
            if response.status_code>=400:
                try:code=response.json()['error']['code']
                except Exception:code='SERVICE_UNAVAILABLE'
                raise VoiceError(code)
            return response
        except VoiceError:raise
        except Exception:raise VoiceError('NETWORK_UNCERTAIN') from None

    async def catalog(self,role):
        profiles=await self.request('GET','/v1/voice-profiles')
        binding=await self.request('GET',f'/v1/characters/{role}/voice-binding')
        return profiles.json()['items'],binding.json()

    async def upload(self,path,name,rid):
        path=Path(path)
        if not 0<path.stat().st_size<=10*1024*1024:raise VoiceError('AUDIO_SIZE_INVALID')
        data=await asyncio.to_thread(path.read_bytes)
        response=await self.request('POST','/v1/voice-profiles',data={'request_id':rid,'name':name,'consent':'true'},
            files={'file':('reference'+path.suffix.lower(),data,'application/octet-stream')})
        return response.json()

    async def job(self,jid):return (await self.request('GET',f'/v1/voice-jobs/{jid}')).json()
    async def cancel(self,jid):return (await self.request('POST',f'/v1/voice-jobs/{jid}/cancel')).json()
    async def retry(self,jid,rid):return (await self.request('POST',f'/v1/voice-jobs/{jid}/retry',json={'request_id':rid})).json()
    async def preview(self,pid,text,rid):
        return (await self.request('POST',f'/v1/voice-profiles/{pid}/previews',json={'text':text,'request_id':rid})).json()
    async def bind(self,role,pid,revision):
        return (await self.request('PUT',f'/v1/characters/{role}/voice-binding',json={'profile_id':pid,'revision':revision})).json()

    async def play(self,device,*,path=None,jid=None):
        await self.stop()
        self.play_task=asyncio.current_task()
        try:
            if path is not None:
                pcm=await asyncio.to_thread(local_pcm,path)
            else:
                response=await self.request('GET',f'/v1/voice-jobs/{jid}/audio')
                with wave.open(io.BytesIO(response.content),'rb') as f:
                    if (f.getnchannels(),f.getsampwidth(),f.getframerate())!=(1,2,24000):
                        raise VoiceError('AUDIO_FORMAT_INVALID')
                    pcm=f.readframes(f.getnframes())
            self.player=Player(device=device)
            self.player.feed(pcm)
            self.player.end()
            while not self.player.finished.is_set():await asyncio.sleep(.05)
            return {'seconds':len(pcm)/48000,**self.player.metrics()}
        except asyncio.CancelledError:
            return {'stopped':True}
        finally:
            if self.player:self.player.close();self.player=None
            self.play_task=None

    async def stop(self):
        task=self.play_task
        if task and task is not asyncio.current_task() and not task.done():
            if self.player:self.player.close()
            task.cancel()
            await task

    async def close(self):
        await self.stop()
        await self.http.aclose()
