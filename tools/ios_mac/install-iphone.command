#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ "$(uname -s)" != Darwin ]]; then echo "请在 Mac 上运行。"; exit 1; fi
root="$(pwd)"
config="$root/.model-local/ios-mac/iphone.json"
if [[ ! -f "$config" ]]; then echo "请先启动测试网关，保持其终端运行。"; exit 1; fi
cd apps/mobile_poc
flutter pub get --enforce-lockfile
flutter build ios --config-only --release --no-codesign --dart-define-from-file="$config"
open ios/Runner.xcworkspace
echo '请在 Xcode 的 Runner target → Signing & Capabilities 中选自己的 Personal Team，勾选自动签名，并确认 Bundle Identifier 可注册。'
read -r -p '保存签名设置、连接并解锁 iPhone 后按回车。' _
flutter devices
read -r -p '输入上方 iPhone 旁的设备 ID：' phone
if [[ -z "$phone" ]]; then echo "缺少 iPhone 设备 ID。"; exit 1; fi
flutter run --release --no-resident --no-pub -d "$phone" --dart-define-from-file="$config"
