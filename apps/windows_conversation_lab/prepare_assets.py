"""Install pinned, integrity-checked browser VAD assets; no runtime CDN calls."""
import base64
import hashlib
import io
from pathlib import Path
import tarfile
from urllib.request import urlopen

PACKAGES = [
    ('vad', 'https://registry.npmjs.org/@ricky0123/vad-web/-/vad-web-0.0.30.tgz',
     'cJyYrh4YeeUBJcbR9Bic/bFDyB9qBkAepvpuWM3vLxnAi7bC3VHzf51UeNdT+OtY4D7MLAgV8iJMc4z41ZnaWg=='),
    ('ort', 'https://registry.npmjs.org/onnxruntime-web/-/onnxruntime-web-1.22.0.tgz',
     'Ud/+EBo6mhuaQWt/OjaOk0iNWjXqJoeeMFr6xQEERZdIZH2OWpGzuujz7lfuOBjUa6TEE/sc4nb7Da5dNL34fg=='),
]


def prepare(root):
    root.mkdir(parents=True, exist_ok=True)
    for name, url, integrity in PACKAGES:
        target = root/name
        marker = target/'integrity.txt'
        if marker.exists() and marker.read_text() == integrity:
            continue
        with urlopen(url, timeout=60) as response:
            data = response.read(100*1024*1024)
        if base64.b64encode(hashlib.sha512(data).digest()).decode() != integrity:
            raise RuntimeError('Asset integrity mismatch: '+name)
        target.mkdir(exist_ok=True)
        with tarfile.open(fileobj=io.BytesIO(data)) as archive:
            for entry in archive:
                path = Path(entry.name)
                if not entry.isfile():
                    continue
                # Only direct files; never extract archive paths or symlinks.
                is_dist = path.parent.as_posix() == 'package/dist'
                wanted = (name == 'vad' and path.name in ('bundle.min.js','vad.worklet.bundle.min.js','silero_vad_v5.onnx'))
                wanted |= name == 'ort' and (path.name == 'ort.wasm.min.js' or path.suffix in ('.wasm','.mjs'))
                license_file = path.parent.as_posix() == 'package' and path.name.upper().startswith(('LICENSE','NOTICE'))
                if (is_dist and wanted) or license_file:
                    (target/path.name).write_bytes(archive.extractfile(entry).read())
        marker.write_text(integrity)
        print('Prepared '+name)


if __name__ == '__main__':
    prepare(Path(__file__).resolve().parents[2]/'.model-local'/'conversation-assets')
