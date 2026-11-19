"""One synthetic chat + voice request through a running gateway (live may bill)."""
import argparse
import json
import time
import uuid
from pathlib import Path
import httpx


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', default='http://127.0.0.1:8787')
    parser.add_argument('--token-file', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    directory = Path(args.output)
    directory.mkdir(parents=True, exist_ok=True)
    token = Path(args.token_file).read_text(encoding='utf-8-sig').strip()
    rid = uuid.uuid4().hex
    started = time.monotonic()
    with httpx.Client(base_url=args.url, headers={'Authorization': 'Bearer '+token}, timeout=110, trust_env=False) as client:
        health = client.get('/health').json()
        with client.stream('POST', '/v1/conversations/local-xing/messages', json={
            'request_id': rid, 'character_id': 'xing', 'content': '请用一句简短中文向我问好，不超过二十个字。', 'history': [],
        }) as response:
            response.raise_for_status()
            text = ''
            completed = False
            first_text = None
            for line in response.iter_lines():
                if not line.startswith('data:'): continue
                packet = json.loads(line[5:])
                if packet['event'] == 'message.delta':
                    first_text = first_text or time.monotonic() - started
                if packet['event'] == 'message.completed':
                    text = packet['content']
                    completed = True
                if packet['event'] in ('message.failed', 'message.cancelled'):
                    raise RuntimeError(packet['code'])
        if not completed or not text: raise RuntimeError('No completed reply')
        chat_seconds = time.monotonic() - started
        audio_started = time.monotonic()
        audio = client.post('/v1/audio/speech', json={
            'request_id': uuid.uuid4().hex, 'reply_request_id': rid, 'character_id': 'xing',
        })
        if audio.status_code != 200: raise RuntimeError(audio.json()['error']['code'])
        if not audio.content.startswith(b'RIFF') or len(audio.content) <= 44: raise RuntimeError('Invalid WAV')
        (directory/'smoke.wav').write_bytes(audio.content)
        result = {'mode': health['mode'], 'chat_completed': completed, 'reply_characters': len(text),
                  'first_text_seconds': first_text, 'chat_seconds': chat_seconds,
                  'voice_seconds': time.monotonic()-audio_started, 'wav_bytes': len(audio.content),
                  'audibility': 'pending human review', 'asr': health['asr']}
        (directory/'result.json').write_text(json.dumps(result, indent=2), encoding='utf8')
        print(json.dumps(result))


if __name__ == '__main__': main()
