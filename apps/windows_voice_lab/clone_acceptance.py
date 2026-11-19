"""Opt-in live acceptance: uses paid providers and plays synthetic test speech.

Keep --output in an ignored local directory. This never opens the normal chat DB.
"""
import argparse
import asyncio
import json
import math
from pathlib import Path
import time
import uuid

from client import Client, load_config
from player import default_output, output_devices
from voice_client import VoiceClient


async def main(args):
    args.output.mkdir(parents=True, exist_ok=True)
    url,token=load_config(args.config)
    voice=VoiceClient(url,token)
    chat=Client(url,token,args.output/'acceptance-history.sqlite')
    device=default_output(output_devices())
    result={'human_listening':'pending','clock':'PortAudio DAC estimate, not acoustic measurement',
            'trials':[]}
    def save():
        (args.output/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    async def finished(job):
        deadline=time.monotonic()+150
        while job['status'] in ('running','unknown') and time.monotonic()<deadline:
            await asyncio.sleep(1)
            job=await voice.job(job['id'])
        if job['status']!='complete':raise RuntimeError('VOICE_JOB_'+job['status'])
        return job
    try:
        before,binding=await voice.catalog('xing')
        _,other=await voice.catalog('yue')
        job=await voice.upload(args.reference,'合成参考验收',uuid.uuid4().hex)
        job=await finished(job)
        pid=job['profile_id']
        duplicate=await voice.upload(args.reference,'合成参考验收',uuid.uuid4().hex)
        result['duplicate_reused']=duplicate['profile_id']==pid
        result['original_playback']=await voice.play(device,path=args.reference)
        result['previews']=[]
        for text in ['你好，很高兴认识你。','今天的天气不错，我们一起去公园散步吧。','现在是下午三点半，别忘了喝水，也让眼睛休息一会儿。']:
            started=time.perf_counter()
            preview=await finished(await voice.preview(pid,text,uuid.uuid4().hex))
            result['previews'].append({'generation_and_poll_ms':(time.perf_counter()-started)*1000,
                                      'playback':await voice.play(device,jid=preview['id'])})
        result['binding']=await voice.bind('xing',pid,binding['revision'])
        _,after_other=await voice.catalog('yue')
        result['other_role_unchanged']=other==after_other
        save()
        # Previews have already warmed the connection. Exclude the first chat from statistics;
        # it is not a cold-start measurement. Next 20 calls measure text -> device output.
        for i in range(args.warm_trials+1):
            await chat.run('请只回复“你好，我在这里。”',device=device)
            trial={'index':i,'error':chat.last_error,**chat.metrics}
            result['trials'].append(trial);save()
            print(json.dumps(trial,ensure_ascii=True),flush=True)
            if chat.last_error:break
        warm=[x['text_to_output_ms'] for x in result['trials'][1:] if not x['error'] and 'text_to_output_ms' in x]
        if warm:
            warm.sort()
            result['warm_summary']={'n':len(warm),'p50_ms':warm[math.ceil(.5*len(warm))-1],
                                    'p95_ms':warm[math.ceil(.95*len(warm))-1], 'max_ms':max(warm)}
        # Cancel actual device playback, then retry speech without repeating DeepSeek.
        task=asyncio.create_task(chat.run('请用一百字介绍春天的公园。',device=device))
        deadline=time.monotonic()+60
        while not task.done() and time.monotonic()<deadline:
            if chat.player and chat.player.first_output is not None:break
            await asyncio.sleep(.05)
        had_output=bool(chat.player and chat.player.first_output is not None)
        started=time.perf_counter();await chat.stop();await task
        result['stop']={'had_output':had_output,'ms':(time.perf_counter()-started)*1000,
                        'text_preserved':chat.store.last('xing')['text_state']=='complete'}
        await chat.run(voice_retry=True,device=device)
        result['speech_retry']={'error':chat.last_error,**chat.metrics}
        rows=len(chat.store.rows('xing'))
        await chat.close()
        chat=Client(url,token,args.output/'acceptance-history.sqlite')
        result['history_reopened']=len(chat.store.rows('xing'))==rows
        save()
        print(json.dumps({'done':True,'summary':result.get('warm_summary'),'stop':result['stop']},ensure_ascii=True),flush=True)
    finally:
        save()
        await chat.close();await voice.close()


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',type=Path,required=True)
    parser.add_argument('--reference',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--warm-trials',type=int,default=20,choices=range(1,51))
    asyncio.run(main(parser.parse_args()))
