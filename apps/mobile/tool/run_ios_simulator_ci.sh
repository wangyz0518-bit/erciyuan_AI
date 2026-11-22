#!/usr/bin/env bash
# #40: real hosted macOS/Xcode iOS Simulator build, install, launch and UI test.
# No Apple signing, physical device, paid API, or production model credentials.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT/apps/mobile"
ARTIFACTS="$ROOT/artifacts/official-ios-simulator"
mkdir -p "$ARTIFACTS"

xcodebuild -version
xcrun simctl list devices available

# The ONNX Runtime binary target is vendored from NuGet because its upstream CDN
# is retired. Idempotent: a no-op when the xcframework is already in place, so
# this works both on a warm cache and on a clean checkout.
python3 tool/fetch_onnxruntime_ios.py

flutter build ios --simulator --debug --no-codesign

APP="build/ios/iphonesimulator/Runner.app"
test -d "$APP"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
test -n "$BUNDLE_ID"

# Choose an installed iPhone simulator, not an unavailable placeholder.
SIM_ID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)
devices = [
    item
    for runtime, entries in data.get("devices", {}).items()
    if "iOS" in runtime
    for item in entries
    if item.get("isAvailable") and "iPhone" in item.get("name", "")
]
if not devices:
    raise SystemExit("No available iPhone simulator")
print(devices[0]["udid"])
')"
echo "Using iOS Simulator: $SIM_ID"
echo "$SIM_ID" > "$ARTIFACTS/simulator-udid.txt"

if ! xcrun simctl list devices | grep -F "$SIM_ID" | grep -q '(Booted)'; then
  xcrun simctl boot "$SIM_ID"
fi
xcrun simctl bootstatus "$SIM_ID" -b
xcrun simctl install "$SIM_ID" "$APP"
xcrun simctl launch "$SIM_ID" "$BUNDLE_ID"
sleep 10
xcrun simctl io "$SIM_ID" screenshot "$ARTIFACTS/ios-person-home.png"
test -s "$ARTIFACTS/ios-person-home.png"

# The iOS simulator must run the formal same SQLite+UI acceptance where
# present. On a base revision predating #37, record the missing suite;
# #40 cannot be closed until the post-#37 integration run actually succeeds.
if [[ -f integration_test/acceptance_test.dart ]]; then
  # PR #70: run all integration suites in one invocation, including the native PCM sink. A second
  # flutter test process against the same booted iOS Simulator can leave the
  # XCTest/VM service attach waiting indefinitely after the first suite.
  # Bound each suite and the whole run so CI reports a useful failure
  # instead of consuming the full 60-minute macOS job timeout.
  SIM_ID="$SIM_ID" python3 - <<'PY'
import subprocess
try:
    subprocess.run(
        ["flutter", "test", "integration_test", "-d", __import__("os").environ["SIM_ID"], "--reporter", "expanded", "--timeout", "5m"],
        check=True,
        timeout=20 * 60,
    )
except subprocess.TimeoutExpired:
    raise SystemExit("iOS integration suite exceeded 20-minute safety timeout")
PY
else
  echo "NOTICE: official integration tests are absent on this baseline; simulator launch only is verified"
fi

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARTIFACTS/Runner-ios-simulator.zip"
test -s "$ARTIFACTS/Runner-ios-simulator.zip"
