"""Extract only allowlisted, synthetic-test metrics from device logs."""
import argparse
import json
from pathlib import Path

FIELDS = {'case','mode','role','failed','saved','chat','voiceFailed','contextCorrect',
          'firstOutputMs','clock','frames','underruns','underrunsBeforeDrain','underrunsDuringDrain',
          'reused','connection_serial','connection_setup_ms','first_packet_ms','firstChunkAtMs',
          'bytes','chunks','ttsToOutputMs','sendToOutputMs'}


def extract(path, marker):
    rows = []
    if not path:
        return rows
    for line in Path(path).read_text(encoding='utf-8-sig').splitlines():
        if marker in line:
            value = json.loads(line.split(marker, 1)[1])
            rows.append({k:v for k,v in value.items() if k in FIELDS})
    return rows


def percentile(values, fraction):
    values = sorted(values)
    if not values:
        return None
    location = (len(values)-1)*fraction
    low = int(location)
    return round(values[low]+(values[min(low+1,len(values)-1)]-values[low])*(location-low), 3)


def stats(rows):
    valid = [r for r in rows if not r.get('failed') and not r.get('voiceFailed') and 'ttsToOutputMs' in r]
    result = {'samples':len(rows),'valid_output_samples':len(valid),
              'failed_or_missing_output':len(rows)-len(valid)}
    for name in ('ttsToOutputMs','sendToOutputMs','connection_setup_ms','first_packet_ms'):
        values = [r[name] for r in valid if isinstance(r.get(name), (int,float))]
        result[name] = {'p50':percentile(values,.5),'p95':percentile(values,.95),
                        'max':max(values) if values else None}
    result['before_drain_underrun_samples'] = sum(r.get('underrunsBeforeDrain',0)>0 for r in valid)
    result['during_drain_underrun_samples'] = sum(r.get('underrunsDuringDrain',0)>0 for r in valid)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--benchmark',required=True)
    parser.add_argument('--live')
    parser.add_argument('--out',required=True)
    parser.add_argument('--benchmark-command-clock', action='store_true',
                        help='Historical benchmark send clock started at chat.send, before telemetry correction')
    args = parser.parse_args()
    rows = extract(args.benchmark,'STREAM_BENCHMARK ')
    live = extract(args.live,'STREAM_LIVE ')
    warm = [r for r in rows if r.get('mode')=='reuse' and r.get('reused')]
    output = {'clock_boundary':'Android device output estimate; excludes host/remote audio link',
              'benchmark_send_clock':'chat.send command emission, excludes initial SQLite/connect' if args.benchmark_command_clock else 'ChatController.send acceptance, includes initial SQLite/connect',
              'live_send_clock':'ChatController.send acceptance, includes initial SQLite/connect',
              'percentiles':'linear interpolation at (n-1)*p',
              'fixed_style':'calm, rate=1.0, 24000Hz mono PCM16',
              'cold':stats([r for r in rows if r.get('mode')=='cold']),
              'reuse_phase_initial_cold':stats([r for r in rows if r.get('mode')=='reuse' and not r.get('reused')]),
              'warm':stats(warm), 'live':stats(live), 'benchmark_rows':rows,'live_rows':live}
    # One line per sample keeps the review diff compact; summary remains indented.
    parts = []
    for key,value in output.items():
        if key.endswith('_rows'):
            parts.append('  '+json.dumps(key)+': [\n'+',\n'.join('    '+json.dumps(row,ensure_ascii=False,separators=(',',':')) for row in value)+'\n  ]')
        else:
            parts.append(json.dumps({key:value},ensure_ascii=False,indent=2)[2:-2])
    Path(args.out).write_text('{\n'+',\n'.join(parts)+'\n}\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in output.items() if not k.endswith('_rows')},ensure_ascii=False,indent=2))
