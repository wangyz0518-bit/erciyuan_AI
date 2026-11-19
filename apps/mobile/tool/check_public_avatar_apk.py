"""Check the distributable APK for local Cubism runtime and model resources."""
import sys
from io import BytesIO
from pathlib import PurePosixPath
from zipfile import ZipFile

def is_avatar_resource(name):
    entry = PurePosixPath(name.lower())
    return (
        entry.name == "liblive2d_avatar.so"
        or "live2dcubismcore" in entry.name
        or "live2d_shaders" in entry.parts
        or entry.name.endswith((".moc3", ".model3.json", ".motion3.json"))
    )


with ZipFile(sys.argv[1]) as apk:
    blocked = [name for name in apk.namelist() if is_avatar_resource(name)]
    for name in apk.namelist():
        if name.lower().endswith(".zip"):
            with ZipFile(BytesIO(apk.read(name))) as nested:
                if any(is_avatar_resource(member) for member in nested.namelist()):
                    blocked.append(name)
if blocked:
    raise SystemExit("Local avatar resources in public APK:\n" + "\n".join(blocked))
print("Public APK contains no Cubism native runtime, shaders or model packages.")
