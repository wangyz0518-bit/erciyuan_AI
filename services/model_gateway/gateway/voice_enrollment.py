"""CosyVoice enrollment adapter. Creation ambiguity is never auto-retried."""
import base64
import re

import httpx

from .providers import ProviderError


class Enrollment:
    def __init__(self,settings):
        self.settings=settings
        self.http=httpx.AsyncClient(timeout=httpx.Timeout(30,connect=10),
                                    proxy=settings.voice_proxy,trust_env=False)

    async def request(self,payload,creating=False):
        s=self.settings
        if not s.dashscope_key: raise ProviderError('VOICE_NOT_CONFIGURED')
        if s.workspace and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]{0,127}',s.workspace):
            raise ProviderError('VOICE_NOT_CONFIGURED')
        host=f'{s.workspace}.cn-beijing.maas.aliyuncs.com' if s.workspace else 'dashscope.aliyuncs.com'
        try:
            result=await self.http.post(f'https://{host}/api/v1/services/audio/tts/customization',
                headers={'Authorization':'Bearer '+s.dashscope_key},json={'model':'voice-enrollment','input':payload})
            if result.status_code in (400,401,403,404,422,429):
                raise ProviderError('VOICE_CREATE_REJECTED' if creating else 'VOICE_QUERY_FAILED')
            if result.status_code!=200: raise ValueError('UPSTREAM_ERROR')
            output=result.json().get('output')
            if not isinstance(output,dict): raise ValueError('INVALID_OUTPUT')
            return output
        except ProviderError: raise
        except Exception:
            raise ProviderError('VOICE_RESULT_UNKNOWN' if creating else 'VOICE_QUERY_FAILED') from None

    async def create(self,prefix,audio):
        result=await self.request({'action':'create_voice','target_model':self.settings.voice_model,
            'prefix':prefix,'audio':'data:audio/wav;base64,'+base64.b64encode(audio).decode(),
            'language_hints':['zh'],'max_prompt_audio_length':30.0,'enable_volume_normalization':'false'},creating=True)
        if not isinstance(result.get('voice_id'),str) or not result['voice_id']:
            raise ProviderError('VOICE_RESULT_UNKNOWN')
        return result['voice_id']

    async def query(self,voice):
        result=await self.request({'action':'query_voice','voice_id':voice})
        if result.get('target_model',self.settings.voice_model)!=self.settings.voice_model:
            raise ProviderError('VOICE_MODEL_MISMATCH')
        return result.get('status','UNKNOWN')

    async def find(self,prefix):
        result=await self.request({'action':'list_voice','prefix':prefix,'page_index':0,'page_size':100})
        voices=result.get('voice_list',result.get('voices',[]))
        matches=[v['voice_id'] for v in voices if isinstance(v,dict) and
                 isinstance(v.get('voice_id'),str) and '-'+prefix+'-' in v['voice_id'] and
                 v['voice_id'].startswith(self.settings.voice_model+'-')]
        return matches[0] if len(matches)==1 else None

    async def close(self): await self.http.aclose()
