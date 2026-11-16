"""Independent clone + synthesis-instruction experiment; never imports the chat gateway."""
import argparse
import asyncio
import hashlib
import html
import json
import os
from pathlib import Path
import random
import re
import shutil
import time
from urllib.request import Request, urlopen
import uuid
import wave

import numpy as np
from websockets.asyncio.client import connect

MODEL = 'cosyvoice-v3.5-flash'
RATE = 24000
TEXTS = {
    'a': '今天的阳光很好，我们一起去公园散散步吧。走累了，就坐下来喝杯茶，慢慢聊聊最近的生活。',
    'b': '别着急，我会在这里陪你。先把眼前的事情一件件做好，剩下的问题，我们可以一起想办法。',
}
VARIANTS = {
    'base': ('原音色，不加指令', '', 1.0),
    'slow': ('文字：慢一点', '保持参考音色和原来的说话人身份，用普通话说话，语速比平时慢一些，吐字清楚，不拖长单个字。', 1.0),
    'soft': ('文字：更柔和', '保持参考音色和原来的说话人身份，用普通话说话，声音更柔和、温暖，语气轻柔，保持自然语速，不要耳语。', 1.0),
    'lower': ('文字：音调稍低', '用普通话说话，保留原音色和说话人身份，音调稍微降低，语速自然。', 1.0),
    'husky': ('文字：略带沙哑', '用普通话说话，保留原音色和说话人身份，增加轻微沙哑质感，语速自然。', 1.0),
    'rate085': ('参数对照：语速 0.85', '', .85),
}


def save(path, data):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    temporary.replace(path)


def write_wav(path, pcm):
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm)


def measures(pcm):
    samples = np.frombuffer(pcm, dtype='<i2').astype(np.float64)/32768
    if not samples.size or not np.any(samples):
        raise ValueError('EMPTY_AUDIO')
    n = len(samples)//240
    energy = np.sqrt(np.mean(samples[:n*240].reshape(n, 240)**2, axis=1))
    active = np.flatnonzero(energy > max(.003, float(energy.max())*.05))
    return dict(duration_s=len(samples)/RATE,
                active_span_s=(int(active[-1])-int(active[0])+1)*.01 if active.size else 0,
                rms_dbfs=float(20*np.log10(np.sqrt(np.mean(samples*samples)))),
                peak=float(np.max(np.abs(samples))),
                clipping_fraction=float(np.mean(np.abs(samples)>=32760/32768)))


def verify_reference(local):
    reference = local/'comparison-reference/reference.wav'
    manifest = json.loads((local/'comparison-voices.json').read_text(encoding='utf-8-sig'))
    digest = hashlib.sha256(reference.read_bytes()).hexdigest()
    if digest != manifest['reference_sha256']:
        raise ValueError('REFERENCE_MANIFEST_MISMATCH')
    key = os.environ['DASHSCOPE_API_KEY']
    workspace = json.loads((local/'dashscope-config.json').read_text(encoding='utf-8-sig')).get('workspace_id', '')
    if workspace and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]{0,127}', workspace):
        raise ValueError('INVALID_WORKSPACE')
    # Match the scope fingerprint used by the original enrollment experiment.
    scope = hashlib.sha256((workspace or 'default:'+key).encode()).hexdigest()
    if scope != manifest['workspace_sha256']:
        raise ValueError('VOICE_SCOPE_MISMATCH')
    voice = manifest['voices'][MODEL]
    host = f'{workspace}.cn-beijing.maas.aliyuncs.com' if workspace else 'dashscope.aliyuncs.com'
    body = {'model':'voice-enrollment', 'input':{'action':'query_voice', 'voice_id':voice}}
    request = Request(f'https://{host}/api/v1/services/audio/tts/customization',
                      data=json.dumps(body).encode(),
                      headers={'Authorization':'Bearer '+key, 'Content-Type':'application/json'})
    with urlopen(request, timeout=20) as response:
        result = json.load(response)['output']
    if result.get('status') != 'OK' or result.get('target_model', MODEL) != MODEL:
        raise ValueError('VOICE_NOT_READY')
    return key, host, voice, reference, digest


async def synthesize(ws, voice, variant, text, seed):
    task = uuid.uuid4().hex
    label, instruction, rate = VARIANTS[variant]
    parameters = dict(text_type='PlainText', voice=voice, format='pcm', sample_rate=RATE,
                      rate=rate, pitch=1.0, volume=50, seed=seed)
    if instruction:
        parameters['instruction'] = instruction
    async def send(action, payload):
        await ws.send(json.dumps({'header':{'action':action,'task_id':task,'streaming':'duplex'},
                                  'payload':payload}, ensure_ascii=False))
    await send('run-task', dict(task_group='audio', task='tts', function='SpeechSynthesizer',
                               model=MODEL, parameters=parameters, input={}))
    pcm = bytearray()
    ready = False
    first = None
    start = time.perf_counter()
    chunks = 0
    deadline = time.monotonic()+60
    while True:
        remaining = deadline-time.monotonic()
        if remaining <= 0:
            raise TimeoutError('TASK_TIMEOUT')
        item = await asyncio.wait_for(ws.recv(), min(20,remaining))
        if isinstance(item, bytes):
            if not ready: raise ValueError('AUDIO_BEFORE_READY')
            if first is None: first = time.perf_counter()-start
            pcm.extend(item)
            chunks += 1
            if len(pcm)>12*1024*1024: raise ValueError('AUDIO_LIMIT')
        else:
            header = json.loads(item).get('header', {})
            if header.get('task_id') != task: raise ValueError('TASK_MISMATCH')
            event = header.get('event')
            if event == 'task-started':
                if ready: raise ValueError('DUPLICATE_START')
                ready = True
                await send('continue-task', {'input':{'text':text}})
                await send('finish-task', {'input':{}})
            elif event == 'task-failed':
                raise ValueError('PROVIDER_TASK_FAILED')
            elif event == 'task-finished':
                if not ready or not pcm or len(pcm)%2: raise ValueError('INVALID_PCM')
                return bytes(pcm), dict(first_packet_s=first, synthesis_s=time.perf_counter()-start, chunks=chunks)


def review_page(directory, results):
    by_id = {r['id']:r for r in results if r['status']=='ok'}
    sections = []
    for text_id, text in TEXTS.items():
        for repeat in (1,2):
            cells = []
            for variant,(label,instruction,rate) in VARIANTS.items():
                name = f'{text_id}-r{repeat}-{variant}'
                row = by_id.get(name)
                audio = f'<audio controls preload="none" src="{name}.wav"></audio>' if row else '<p>生成失败，未自动重试</p>'
                cells.append(f'<div class="card"><b>{html.escape(label)}</b><p>{name}</p>{audio}</div>')
            sections.append(f'<section><h2>台词 {text_id.upper()} · 第 {repeat} 轮</h2><p>{text}</p><div class="grid">'+''.join(cells)+'</div></section>')
    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>参考音色＋文字微调 · 独立试听</title>
<style>body{font:16px/1.6 system-ui;background:#f4f4fa;color:#242b40;max-width:1100px;margin:auto;padding:24px}h1{color:#57459a}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:14px}.card,section{background:white;border-radius:12px;padding:18px;margin:12px 0}.card{background:#f1effa}audio{width:100%}button{padding:8px 16px}textarea{width:98%;height:100px}</style>
<h1>参考音色＋文字微调</h1><p>同一复刻音色、相同台词；每轮同一 seed。前五组 rate/pitch 均为 1，最后一组仅用于参数对照。没有调用 DeepSeek，也没有修改正式聊天。</p>
<p>先听参考，再在同一台词内比较：①是否还是同一个声音？②指定变化是否明显？③是否自然、有没有电音或断字？不同文字的音量或时长变化不能证明音色保持。</p>
<div class="card"><b>原始参考：10.96 秒合成语音</b><audio controls preload="none" src="reference.wav"></audio></div>
<button onclick="document.querySelectorAll('audio').forEach(a=>a.pause())">停止播放</button>
'''+''.join(sections)+'''<section><h2>试听记录</h2><p>可填写“a-r1-soft：像同一个人；更柔和；无明显异常”。下载的记录只保存在本机。</p><textarea id="notes"></textarea><p><button onclick="saveNotes()">保存试听记录</button></p></section>
<script>document.querySelectorAll('audio').forEach(a=>a.addEventListener('play',()=>document.querySelectorAll('audio').forEach(b=>{if(a!==b)b.pause()})));function saveNotes(){let b=new Blob([JSON.stringify({human_notes:document.getElementById('notes').value},null,2)],{type:'application/json'});let a=document.createElement('a');a.href=URL.createObjectURL(b);a.download='listening-notes.json';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000)}</script></html>'''
    (directory/'listen.html').write_text(page, encoding='utf-8')


async def main(args):
    for v in args.variants:
        if sum(2 if '\u4e00'<=c<='\u9fff' else 1 for c in VARIANTS[v][1])>100:
            raise ValueError('INSTRUCTION_TOO_LONG')
    args.out.mkdir(parents=True, exist_ok=False)
    # Process-only route: use the already configured proxy; never change system settings.
    os.environ['NO_PROXY'] = '127.0.0.1,localhost'
    key, host, voice, reference, digest = await asyncio.to_thread(verify_reference, args.local)
    shutil.copyfile(reference, args.out/'reference.wav')
    schedule = [(t,r,v) for t in TEXTS for r in (1,2) for v in args.variants]
    random.Random(1601).shuffle(schedule)
    manifest = dict(model=MODEL, reference_sha256=digest, reference_origin='synthetic Qwen Serena',
                    new_voice_created=False, voice_query='OK', same_voice_all_cases=True,
                    texts=TEXTS, variants=VARIANTS, schedule=schedule,
                    llm_calls=0, human_listening='pending', rate=RATE,
                    route='existing HTTPS_PROXY' if os.getenv('HTTPS_PROXY') else 'direct')
    save(args.out/'manifest.json',manifest)
    results=[]
    ws=None
    try:
        for position,(t,r,v) in enumerate(schedule,1):
            name=f'{t}-r{r}-{v}'
            row=dict(id=name,text_id=t,repeat=r,variant=v,seed=41+r,position=position,status='failed')
            try:
                reused=ws is not None
                before=time.perf_counter()
                if ws is None:
                    ws=await connect(f'wss://{host}/api-ws/v1/inference',
                        additional_headers={'Authorization':'Bearer '+key},
                        proxy=os.getenv('HTTPS_PROXY') or None,open_timeout=15,close_timeout=1,max_size=4*1024*1024)
                row.update(connection_reused=reused,connection_s=time.perf_counter()-before)
                pcm,timing=await synthesize(ws,voice,v,TEXTS[t],41+r)
                row.update(measures(pcm),**timing,status='ok',pcm_sha256=hashlib.sha256(pcm).hexdigest())
                write_wav(args.out/(name+'.wav'),pcm)
            except Exception as exc:
                row['error_type']=type(exc).__name__ # Never print supplier bodies/URLs/keys.
                if ws is not None:
                    await ws.close();ws=None
            results.append(row)
            save(args.out/'results.json',results)
            print(json.dumps({'case':name,'status':row['status'],'duration_s':row.get('duration_s'),
                              'first_packet_s':row.get('first_packet_s'),'error':row.get('error_type')},ensure_ascii=True),flush=True)
    finally:
        if ws is not None: await ws.close()
        review_page(args.out,results)
    print('Completed '+str(sum(r['status']=='ok' for r in results))+'/'+str(len(schedule)),flush=True)
    if any(r['status']!='ok' for r in results):
        raise ValueError('SOME_SAMPLES_FAILED')


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--local',type=Path,required=True,help='Existing ignored voice experiment configuration')
    parser.add_argument('--out',type=Path,required=True,help='New ignored artifact directory')
    parser.add_argument('--variants',nargs='+',choices=list(VARIANTS),default=list(VARIANTS))
    args=parser.parse_args()
    try:
        asyncio.run(main(args))
    except Exception as exc:
        print('Experiment stopped: '+type(exc).__name__+'; private details omitted',flush=True)
        raise SystemExit(1)
