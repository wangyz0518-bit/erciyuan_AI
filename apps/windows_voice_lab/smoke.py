"""Explicit real-service/native-output smoke. Uses synthetic prompts, never a microphone."""
import argparse
import asyncio
import json
import time
from pathlib import Path

from client import Client, load_config
from player import default_output, output_devices
from store import Store


async def exercise(config, directory):
    directory.mkdir(parents=True, exist_ok=False)
    url, token = load_config(config)
    path = directory/'test.sqlite'
    client = Client(url, token, path)
    device = default_output(output_devices())
    rows = []

    def record(name):
        row = client.store.last(client.role)
        result = dict(case=name, text_state=row['text_state'], audio_state=row['audio_state'],
                      error=client.last_error, **client.metrics)
        rows.append(result)
        print(json.dumps(result, ensure_ascii=False), flush=True)
        (directory/'metrics.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')

    try:
        await client.run('请用十个字以内的中文向我问好。', device=device)
        record('short-xing')
        assert client.store.last('xing')['audio_state'] == 'complete'
        await client.run(voice_retry=True, device=device)
        record('voice-only-retry')
        assert len(client.store.rows('xing')) == 1
        assert client.store.last('xing')['audio_state'] == 'complete'
        await client.select('yue')
        await client.run('请用十五字以内的中文描述晴天。', device=device)
        record('short-yue')
        assert client.store.last('yue')['audio_state'] == 'complete'
        job = asyncio.create_task(client.run('请用约一百字中文描述星空，写成一段自然的话。', device=device))
        deadline = time.monotonic()+100
        while not job.done() and time.monotonic()<deadline:
            if client.player and client.player.first_output is not None:
                break
            await asyncio.sleep(.02)
        assert client.player and client.player.first_output is not None, 'No native output before cancellation'
        before = time.perf_counter()
        await client.stop()
        await job
        client.metrics['stop_ms'] = (time.perf_counter()-before)*1000
        record('stop-during-playback')
        assert client.store.last('yue')['text_state'] == 'complete'
        assert client.store.last('yue')['audio_state'] == 'cancelled'
        assert client.player is None
    finally:
        await client.close()
    restored = Store(path)
    try:
        assert len(restored.rows('xing')) == 1 and len(restored.rows('yue')) == 2
        assert restored.last('yue')['text_state'] == 'complete'
    finally:
        restored.close()
    print('WINDOWS_SMOKE passed; text recovery=true; acoustic_listening=not_asserted', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    asyncio.run(exercise(args.config, args.out))
