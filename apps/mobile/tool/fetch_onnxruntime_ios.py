#!/usr/bin/env python3
"""Materialise the ONNX Runtime iOS xcframework into ios/ConversationVAD/Vendor/.

Why this exists
---------------
`ios/ConversationVAD/Package.swift` used to declare the binary target as a
remote URL:

    .binaryTarget(name: "onnxruntime",
                  url: "https://download.onnxruntime.ai/pod-archive-onnxruntime-c-<v>.zip",
                  checksum: "...")

That host is gone. It now CNAMEs to `onnxruntimepackages.azureedge.net`, whose
Azure Front Door configuration returns a "Page not found / configuration not
found" page for every path and every version, and whose TLS certificate is the
generic `*.azureedge.net` wildcard -- which does not cover
`download.onnxruntime.ai`, hence the `hostname mismatch` Xcode reports before it
ever gets to see the 404.

CocoaPods is not a workaround: `onnxruntime-c.podspec.json` up to 1.30.0 points
at the same dead URL.

NuGet still publishes the identical build. `Microsoft.ML.OnnxRuntime` carries
`runtimes/ios/native/onnxruntime.xcframework.zip`, which is a universal iOS
xcframework (device arm64 + simulator arm64/x86_64) with the full C/C++ headers
including `onnxruntime_cxx_api.h`, which `ConversationVAD.cpp` needs. The binary
reports version 1.24.2, matching the podspec's `version` and its
`static_framework: True` flag.

So the fix is to vendor the framework locally and switch the target to
`.binaryTarget(name:path:)`. Nothing is downloaded at build time, so Xcode
resolves the package even with no network.

Sources, in priority order
--------------------------
1. `ORT_IOS_XCFRAMEWORK_ZIP` -- path to an already-extracted
   `onnxruntime.xcframework.zip` (an internal cache / artefact mirror).
2. `ORT_IOS_XCFRAMEWORK_URL` -- URL of that same zip (a self-hosted mirror).
3. NuGet flat container (default).

Exit codes
----------
0  the framework is in place (fetched now, or already present)
1  could not obtain it; the message says what to do instead
"""

from __future__ import annotations

import hashlib
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

# Pinned to the version the app was built against. Bump together with the
# silero_vad_v5.onnx model's expected operator set, not on a whim.
VERSION = "1.24.2"

# sha256 of the inner `runtimes/ios/native/onnxruntime.xcframework.zip` for
# VERSION. This is the exact payload that used to sit behind the dead CDN URL,
# so a match proves we vendored the same build rather than something adjacent.
INNER_SHA256 = "a161fe8628ed3bf8d97915bd34063fe115f58a1b9b0f4f0baec78c62487ac3ee"

NUPKG_URL = (
    "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/"
    f"{VERSION}/microsoft.ml.onnxruntime.{VERSION}.nupkg"
)
INNER_MEMBER = "runtimes/ios/native/onnxruntime.xcframework.zip"

APP_DIR = Path(__file__).resolve().parent.parent
TARGET = APP_DIR / "ios" / "ConversationVAD" / "Vendor" / "onnxruntime.xcframework"

# Slices this app actually builds for. maccatalyst is 82 MB of dead weight and
# declares a platform the Flutter target never requests.
KEEP_SLICES = ("ios-arm64", "ios-arm64_x86_64-simulator")

MARKER = ".ort-ios-version"


def log(msg: str) -> None:
    print(f"[ort-ios] {msg}", flush=True)


def die(msg: str) -> None:
    print(f"[ort-ios] error: {msg}", file=sys.stderr, flush=True)
    raise SystemExit(1)


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def is_ready() -> bool:
    """True when a complete, correct-version xcframework is already vendored."""
    info = TARGET / "Info.plist"
    marker = TARGET / MARKER
    if not info.is_file() or not marker.is_file():
        return False
    if marker.read_text().strip() != VERSION:
        return False
    return all((TARGET / s).is_dir() for s in KEEP_SLICES)


def download(url: str, dest: Path) -> None:
    log(f"downloading {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "erciyuan-ci"})
    with urllib.request.urlopen(req, timeout=300) as resp, dest.open("wb") as fh:
        total = int(resp.headers.get("Content-Length") or 0)
        seen = 0
        next_note = 0
        while True:
            chunk = resp.read(1 << 20)
            if not chunk:
                break
            fh.write(chunk)
            seen += len(chunk)
            if total and seen >= next_note:
                log(f"  {seen * 100 // total}% ({seen // (1 << 20)} MiB)")
                next_note = seen + max(total // 5, 1 << 24)
    log(f"got {dest.stat().st_size // (1 << 20)} MiB")


def obtain_inner_zip(work: Path) -> Path:
    """Return a path to `onnxruntime.xcframework.zip`, however we can get it."""
    local = os.environ.get("ORT_IOS_XCFRAMEWORK_ZIP")
    if local:
        p = Path(local).expanduser()
        if not p.is_file():
            die(f"ORT_IOS_XCFRAMEWORK_ZIP={local} does not exist")
        log(f"using local zip {p}")
        return p

    mirror = os.environ.get("ORT_IOS_XCFRAMEWORK_URL")
    target = work / "xcframework.zip"
    if mirror:
        log("ORT_IOS_XCFRAMEWORK_URL is set, using the mirror instead of NuGet")
        download(mirror, target)
        return target

    nupkg = work / "ort.nupkg"
    download(NUPKG_URL, nupkg)
    try:
        with zipfile.ZipFile(nupkg) as zf:
            zf.extract(INNER_MEMBER, work)
    except KeyError:
        die(f"{NUPKG_URL} did not contain {INNER_MEMBER}; the package layout changed")
    return work / INNER_MEMBER


def unzip_xcframework(zip_path: Path, dest_parent: Path) -> Path:
    with zipfile.ZipFile(zip_path) as zf:
        names = zf.namelist()
        if not any(n.startswith("onnxruntime.xcframework/") for n in names):
            die(f"{zip_path.name} does not contain onnxruntime.xcframework/")
        zf.extractall(dest_parent)
    out = dest_parent / "onnxruntime.xcframework"
    if not (out / "Info.plist").is_file():
        die("extracted payload has no Info.plist; refusing to install it")
    return out


def prune(xcf: Path) -> None:
    for child in sorted(xcf.iterdir()):
        if child.is_dir() and child.name not in KEEP_SLICES:
            log(f"dropping unused slice {child.name}")
            shutil.rmtree(child)


def check_cxx_header(xcf: Path) -> None:
    """ConversationVAD.cpp includes onnxruntime_cxx_api.h; fail early if absent."""
    for slice_name in KEEP_SLICES:
        fw = xcf / slice_name / "onnxruntime.framework"
        header = fw / "Headers" / "onnxruntime_cxx_api.h"
        if not header.is_file():
            die(f"{slice_name} has no onnxruntime_cxx_api.h; ConversationVAD will not compile")


def binary_reports_version(path: Path, version: str) -> bool:
    """True when the device slice embeds this version string.

    Guards against vendoring a NuGet build that drifted from the pin. It is a
    heuristic (a version literal could in principle appear for another reason),
    so callers treat a miss as a warning rather than a hard failure.
    """
    bin_path = path / "ios-arm64" / "onnxruntime.framework" / "onnxruntime"
    if not bin_path.is_file():
        return False
    try:
        return version.encode() in bin_path.read_bytes()
    except OSError:
        return False


def main() -> int:
    if is_ready():
        log(f"already vendored at {TARGET.relative_to(APP_DIR)} (v{VERSION})")
        return 0

    if TARGET.exists():
        log("found an incomplete or mismatched vendor dir, rebuilding it")
        shutil.rmtree(TARGET)

    TARGET.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="ort-ios-") as tmp:
        work = Path(tmp)
        inner = obtain_inner_zip(work)

        digest = sha256_of(inner)
        log(f"inner zip sha256 {digest}")
        if INNER_SHA256 and digest != INNER_SHA256:
            die(
                f"payload checksum mismatch for v{VERSION}.\n"
                f"  expected {INNER_SHA256}\n"
                f"  got      {digest}\n"
                "Refusing to vendor an unexpected build. If a mirror was used, "
                "check that it serves the same archive as NuGet."
            )

        extracted = unzip_xcframework(inner, work / "x")
        prune(extracted)
        check_cxx_header(extracted)

        if not binary_reports_version(extracted, VERSION):
            log(f"warning: could not confirm '{VERSION}' inside the binary; continuing")

        shutil.copytree(extracted, TARGET)
        (TARGET / MARKER).write_text(VERSION + "\n")

    total = sum(f.stat().st_size for f in TARGET.rglob("*") if f.is_file())
    log(f"installed {TARGET.relative_to(APP_DIR)} ({total // (1 << 20)} MiB, v{VERSION})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())