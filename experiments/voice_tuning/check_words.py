"""Optional local SenseVoice audit of synthetic outputs; not a speaker-identity score."""
import argparse
import json
from pathlib import Path
import re

import sherpa_onnx
import soundfile as sf


def normal(text):
    return re.sub(r'[^\u4e00-\u9fffA-Za-z0-9]', '', text).lower()


def distance(a,b):
    previous=list(range(len(b)+1))
    for i,x in enumerate(a,1):
        current=[i]
        for j,y in enumerate(b,1):
            current.append(min(current[-1]+1,previous[j]+1,previous[j-1]+(x!=y)))
        previous=current
    return previous[-1]


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--directory',type=Path,required=True)
    parser.add_argument('--model',type=Path,required=True)
    args=parser.parse_args()
    manifest=json.loads((args.directory/'manifest.json').read_text(encoding='utf-8'))
    rows=json.loads((args.directory/'results.json').read_text(encoding='utf-8'))
    recognizer=sherpa_onnx.OfflineRecognizer.from_sense_voice(
        model=str(args.model/'model.int8.onnx'),tokens=str(args.model/'tokens.txt'),
        num_threads=4,language='zh',use_itn=True)
    checks=[]
    for row in rows:
        if row['status']!='ok':continue
        samples,rate=sf.read(args.directory/(row['id']+'.wav'),dtype='float32')
        stream=recognizer.create_stream()
        stream.accept_waveform(rate,samples)
        recognizer.decode_stream(stream)
        expected=manifest['texts'][row['text_id']]
        recognized=stream.result.text
        edit=distance(normal(expected),normal(recognized))
        checks.append(dict(id=row['id'],expected=expected,recognized=recognized,edit_distance=edit))
        print(row['id']+' edit_distance='+str(edit),flush=True)
    (args.directory/'asr-checks.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2),encoding='utf-8')
    print('ASR exact matches: '+str(sum(c['edit_distance']==0 for c in checks))+'/'+str(len(checks)),flush=True)
