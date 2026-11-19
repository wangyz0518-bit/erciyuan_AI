#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ "$(uname -s)" != Darwin ]]; then echo "请在 Mac 上运行。"; exit 1; fi
umask 077
if command -v python3.12 >/dev/null; then python_bin=python3.12; else python_bin=python3; fi
"$python_bin" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else "请安装 Python 3.12。")'
venv=".model-local/ios-mac/venv"
if [[ ! -x "$venv/bin/python" ]]; then "$python_bin" -m venv "$venv"; fi
"$venv/bin/python" -m pip install --disable-pip-version-check -q -r services/model_gateway/requirements-lock.txt 'cryptography>=42'
iface="$(route -n get default 2>/dev/null | awk '/interface:/ {print $2; exit}')"
suggested="$(ipconfig getifaddr "${iface:-en0}" 2>/dev/null || ipconfig getifaddr en0 2>/dev/null || true)"
read -r -p "Mac 与 iPhone 同一 Wi-Fi 上的 Mac IPv4 地址 [$suggested]：" wifi_ip
exec "$venv/bin/python" services/model_gateway/ios_test_gateway.py --host "${wifi_ip:-$suggested}" "$@"
