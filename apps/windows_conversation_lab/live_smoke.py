"""Explicit paid synthetic end-to-end test. Does not open any microphone.

Creates a TTS reference through v3, resamples it, submits as a voice message,
then verifies ASR -> DeepSeek -> TTS. Never reports playback as heard.
"""
import argparse
import asyncio
import audioop
import json
from pathlib import Path
import struct
import time
import uuid

from websockets.asyncio.client import connect


def decode(raw):
    if isinstance(raw, bytes):
        size = struct.unpack('!I',raw[:4])[0]
        return json.loads(raw[4:4+size]), raw[4+size:]
    return json.loads(raw), None


async def exercise(data, report, output):
    url = data['MODEL_GATEWAY_URL'].replace('http://','ws://')+'/v3/conversations/yue/stream'
    async with connect(url,proxy=None,max_size=1024*1024) as ws:
        async def send(**fields):await ws.send(json.dumps(fields,ensure_ascii=False))
        async def collect(target):
            chunks=bytearray();text='';start=time.monotonic()
            async with asyncio.timeout(120):
                while True:
                    packet,pcm=decode(await ws.recv())
                    report['events'].append({'event':packet['event'],'seconds':round(time.monotonic()-start,3)})
                    if packet['event'] in ('turn.failed','request.failed','input.failed','session.failed'):
                        raise RuntimeError(packet.get('code','FAILED'))
                    if packet['event']=='transcript.final':report['transcript']=packet['text']
                    if packet['event']=='reply.saved':text=packet['text']
                    if pcm:chunks.extend(pcm)
                    if packet['event']==target:return text,bytes(chunks)
        await send(command='session.start',token=data['MODEL_GATEWAY_TOKEN'])
        await collect('session.ready')
        rid=uuid.uuid4().hex
        await send(command='chat.send',request_id=rid,text='请只回复这一句，不要添加其他内容：你好，我今天想聊一聊星星。',speak=True)
        reference,pcm=await collect('audio.completed')
        report['reference_text']=reference;report['reference_bytes']=len(pcm)
        (output/'synthetic-reference.pcm').write_bytes(pcm)
        await send(command='turn.interrupt',reply_id=rid)
        await collect('interrupt.accepted')
        converted,_=audioop.ratecv(pcm,2,1,24000,16000,None)
        rid=uuid.uuid4().hex
        await send(command='input.start',input_id=rid,kind='hold')
        await collect('input.ready')
        for seq,offset in enumerate(range(0,len(converted),1600)):
            header=json.dumps({'input_id':rid,'seq':seq}).encode()
            await ws.send(struct.pack('!I',len(header))+header+converted[offset:offset+1600])
            await asyncio.sleep(.05)
        await send(command='input.commit',input_id=rid)
        reply,audio=await collect('audio.completed')
        report['reply_text']=reply;report['reply_bytes']=len(audio)
        report['passed']=bool(report.get('transcript') and audio)
        await send(command='session.end')


async def main(config, output):
    data = json.loads(config.read_text(encoding='utf-8-sig'))
    output.mkdir(parents=True, exist_ok=True)
    report = {'passed':False,'microphone_tested':False,'playback_tested':False,'reference':'synthetic', 'events':[]}
    try:
        await exercise(data, report, output)
    except Exception as exc:
        # Only our fixed protocol error codes may be written; no transport
        # exception, URL, authorization header or private configuration.
        value=str(exc)
        report['error']=value if isinstance(exc,RuntimeError) and value.replace('_','').isupper() and len(value)<80 else type(exc).__name__
    (output/'synthetic-smoke.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:report[k] for k in ('passed','error','reference_text','transcript','reference_bytes','reply_bytes') if k in report},ensure_ascii=False))
    if not report['passed']:
        raise SystemExit(1)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--config',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();asyncio.run(main(args.config,args.output))
