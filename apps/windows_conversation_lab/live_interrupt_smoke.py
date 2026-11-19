"""Paid live call protocol test using a previously generated synthetic clip.

No microphone or device playback is used. Playback acknowledgement is never
fabricated; this validates upstream cancellation and independent next input.
"""
import argparse
import asyncio
import audioop
import json
from pathlib import Path
import struct
import uuid

from websockets.asyncio.client import connect

from live_smoke import decode


async def exercise(data, reference, report):
    pcm, _ = audioop.ratecv(reference.read_bytes(), 2, 1, 24000, 16000, None)
    url = data['MODEL_GATEWAY_URL'].replace('http://','ws://')+'/v3/conversations/xing/stream'
    async with connect(url, proxy=None, max_size=1024*1024) as ws:
        async def send(**packet): await ws.send(json.dumps(packet))
        async def take(event, rid=None):
            async with asyncio.timeout(120):
                while True:
                    p, audio = decode(await ws.recv())
                    if p['event'] in ('turn.failed','input.failed','request.failed','session.failed'):
                        raise RuntimeError(p.get('code','FAILED'))
                    if report.get('interrupted') and p.get('reply_id') == report['first_id'] and audio:
                        raise RuntimeError('OLD_AUDIO_AFTER_CANCEL_ACK')
                    if p['event'] == 'transcript.final':
                        report.setdefault('transcripts', []).append(p['text'])
                    if p['event'] == event and (rid is None or p.get('reply_id',p.get('input_id')) == rid):
                        return p
        async def feed(rid):
            for seq, offset in enumerate(range(0,len(pcm),1600)):
                head=json.dumps({'input_id':rid,'seq':seq}).encode()
                await ws.send(struct.pack('!I',len(head))+head+pcm[offset:offset+1600])
                await asyncio.sleep(.05)
            await send(command='input.commit',input_id=rid)
        await send(command='session.start',token=data['MODEL_GATEWAY_TOKEN'])
        await take('session.ready')
        first, second, aborted = (uuid.uuid4().hex for _ in range(3))
        report['first_id']=first
        await send(command='input.start',input_id=first,kind='call')
        await take('input.ready'); await feed(first)
        await take('audio.chunk',first)
        await send(command='turn.interrupt',reply_id=first)
        # New input starts without waiting for the old synthesis to finish.
        await send(command='input.start',input_id=second,kind='call')
        ack=await take('interrupt.accepted',first)
        assert not ack['stale']
        report['interrupted']=True
        await take('input.ready',second); await feed(second)
        audio=await take('audio.completed',second)
        report['second_audio_frames']=audio['total_frames']
        await send(command='turn.interrupt',reply_id=second)
        await take('interrupt.accepted',second)
        await send(command='input.start',input_id=aborted,kind='hold')
        await take('input.ready',aborted)
        await send(command='input.abort',input_id=aborted)
        await take('input.aborted',aborted)
        await send(command='session.end')
        await ws.wait_closed()
    import httpx
    async with httpx.AsyncClient(trust_env=False) as client:
        response=await client.get(data['MODEL_GATEWAY_URL']+'/v3/conversations/xing',headers={'Authorization':'Bearer '+data['MODEL_GATEWAY_TOKEN']})
        response.raise_for_status()
        rows={row['id']:row for row in response.json()['items']}
    assert rows[first]['audio_state']=='interrupted' and rows[first]['played_frames']==0
    assert not rows[first]['has_recording'] and not rows[second]['has_recording']
    assert aborted not in rows
    assert len(report.get('transcripts',[]))==2 and audio['total_frames']>0
    report.update(passed=True,call_raw_audio_retained=False,aborted_input_saved=False)


async def main(config, reference, output):
    data=json.loads(config.read_text(encoding='utf-8-sig'))
    report={'passed':False,'microphone_tested':False,'playback_tested':False,'reference':'synthetic'}
    try:
        await exercise(data,reference,report)
    except Exception as exc:
        value=str(exc)
        report['error']=value if isinstance(exc,RuntimeError) and value.replace('_','').isupper() and len(value)<80 else type(exc).__name__
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='first_id'},ensure_ascii=False))
    if not report['passed']:raise SystemExit(1)


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--config',type=Path,required=True)
    parser.add_argument('--reference',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    asyncio.run(main(args.config,args.reference,args.output))
