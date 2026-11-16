"""Bounded local decoder. Never accepts URLs, playlists, or remote protocols."""
import array
import io
import math
from pathlib import Path
import re
import subprocess
import sys
import wave

import imageio_ffmpeg

from .providers import ProviderError

MAX_UPLOAD = 10 * 1024 * 1024


def normalize(path: Path) -> tuple[bytes, dict]:
    if not 0 < path.stat().st_size <= MAX_UPLOAD:
        raise ProviderError('AUDIO_SIZE_INVALID')
    signature = path.read_bytes()[:16]
    if signature[:4] == b'RIFF' and signature[8:12] == b'WAVE':
        fmt = 'wav'
    elif signature[:3] == b'ID3' or (len(signature)>1 and signature[0]==255 and signature[1]&224==224):
        fmt = 'mp3'
    elif signature[4:8] == b'ftyp':
        fmt = 'mov'
    else:
        raise ProviderError('AUDIO_FORMAT_INVALID')
    # Decode at most 31s to detect the 30s bound, without processing an unbounded file.
    args = [imageio_ffmpeg.get_ffmpeg_exe(), '-hide_banner', '-nostdin', '-v', 'info',
            '-protocol_whitelist', 'file,pipe', '-f', fmt, '-i', str(path.resolve()),
            '-map', '0:a:0', '-vn', '-t', '31', '-af', 'pan=mono|c0=c0',
            '-ar', '24000', '-ac', '1', '-f', 's16le', 'pipe:1']
    try:
        proc = subprocess.run(args, capture_output=True, timeout=20,
                              creationflags=subprocess.CREATE_NO_WINDOW if sys.platform=='win32' else 0)
    except (OSError, subprocess.TimeoutExpired):
        raise ProviderError('AUDIO_DECODE_FAILED') from None
    match = re.search(r'Audio: [^\n]*?, (\d+) Hz', proc.stderr.decode('utf-8', errors='replace'))
    if proc.returncode or not match or len(proc.stdout)%2:
        raise ProviderError('AUDIO_DECODE_FAILED')
    if int(match[1]) < 16000:
        raise ProviderError('AUDIO_SAMPLE_RATE_LOW')
    duration = len(proc.stdout)/48000
    if not 10 <= duration <= 30:
        raise ProviderError('AUDIO_DURATION_INVALID')
    samples = array.array('h', proc.stdout)
    if sys.byteorder != 'little': samples.byteswap()
    rms = math.sqrt(sum(x*x for x in samples)/len(samples)) / 32768
    active = sum(abs(x)>200 for x in samples)/len(samples)
    if rms < .002 or active < .01:
        raise ProviderError('AUDIO_SILENT')
    out = io.BytesIO()
    with wave.open(out,'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(24000); f.writeframes(proc.stdout)
    return out.getvalue(), {'duration_seconds':round(duration,3), 'sample_rate':24000,
                           'channels':1, 'source_sample_rate':int(match[1]), 'rms':round(rms,5)}
