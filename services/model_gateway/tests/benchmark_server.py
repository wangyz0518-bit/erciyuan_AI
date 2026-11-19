"""Explicit test fixture: fixed synthetic replies + real TTS, never DeepSeek.

Run only on loopback, using tests/run_benchmark.ps1. Not imported by production.
"""
import json
import os

from fastapi import Depends

from gateway.app import create_app as gateway_app
from gateway.providers import Settings
from gateway.speech_pool import SpeechPool


def create_app():
    settings = Settings.env()
    with open(os.environ['BENCHMARK_MANIFEST'], encoding='utf-8-sig') as source:
        cases = json.load(source)['cases']
    mapping = {str(c['id']): c['text'] for c in cases}
    pool = SpeechPool(settings)

    class FixedReplies:
        async def reply(self, character, history, content):
            yield mapping[content]

    app = gateway_app(settings, FixedReplies(), pool)
    # All routes, including fixture control, require the development bearer token.
    from fastapi import Header, HTTPException
    import hmac
    def auth(authorization: str = Header(default='')):
        if not hmac.compare_digest(authorization, 'Bearer '+settings.token):
            raise HTTPException(401)

    @app.get('/benchmark/cases', dependencies=[Depends(auth)])
    async def list_cases():
        return {'cases': [{'id': str(c['id']), 'text': c['text']} for c in cases],
                'deepseek_calls': 0, 'style': 'calm', 'rate': 1.0}

    @app.post('/benchmark/reset', dependencies=[Depends(auth)])
    async def reset():
        if pool.lock.locked():
            raise HTTPException(409)
        await pool.close()
        return {'closed': True}
    return app
