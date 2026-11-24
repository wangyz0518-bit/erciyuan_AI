#!/usr/bin/env bash
# CI-only Android emulator screenshots for the official Flutter app.
# Requires a booted emulator, Flutter, and ADB; never calls a paid API.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCREENSHOTS="$ROOT/artifacts/official-android-emulator-ui"
mkdir -p "$SCREENSHOTS"

# Preserve failure evidence while Android is still running inside the emulator
# runner action. The post-action ADB session is not always available.
capture_device_evidence() {
  local result=$?
  if [[ -n "${gateway_pid:-}" ]]; then kill "$gateway_pid" 2>/dev/null || true; fi
  if [[ "$result" -ne 0 ]]; then
    timeout --signal=TERM --kill-after=2s 15s adb exec-out screencap -p \
      > "$SCREENSHOTS/failure-state.png" || true
  fi
  timeout --signal=TERM --kill-after=2s 15s adb logcat -d -t 2500 -v time \
    > "$SCREENSHOTS/device-logcat.txt" || true
}
trap capture_device_evidence EXIT

export ANDROID_SERIAL="${ANDROID_SERIAL:-emulator-5554}"
adb wait-for-device
adb shell wm size 375x812
adb shell wm density 160
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0

timeout --signal=TERM --kill-after=10s 480s flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am force-stop dev.erciyuan.mobile || true
adb shell am start -n dev.erciyuan.mobile/.MainActivity
# Flutter exposes destination labels and page headings through Android semantics.
# Wait for each actual screen before capturing it, including on slower runners.
wait_label() {
  local label="$1" position
  for _ in {1..10}; do
    if adb shell uiautomator dump /sdcard/official-screen.xml >/dev/null &&
       position=$(adb exec-out cat /sdcard/official-screen.xml | python -c '
import re, sys, xml.etree.ElementTree as ET
target = sys.argv[1]
for node in ET.parse(sys.stdin.buffer).iter("node"):
    labels = [node.get(field, "") for field in ("content-desc", "text", "tooltip-text")]
    if any(target in value.splitlines() for value in labels):
        left, top, right, bottom = map(int, re.findall(r"\d+", node.attrib["bounds"]))
        print((left + right) // 2, (top + bottom) // 2)
        break
else:
    sys.exit(1)
' "$label"); then
      echo "$position"
      return 0
    fi
    sleep 1
  done
  echo "Missing Android accessibility label: $label" >&2
  return 1
}

tap_label() {
  local position x y
  position=$(wait_label "$1")
  read -r x y <<< "$position"
  adb shell input tap "$x" "$y"
}

wait_label '切换人物' >/dev/null
adb exec-out screencap -p > "$SCREENSHOTS/continuous-chat.png"
tap_label '角色'
wait_label '今天想和谁聊聊？' >/dev/null
adb exec-out screencap -p > "$SCREENSHOTS/person-home.png"
tap_label '我的'
tap_label '本机数据管理'
wait_label '导出全部人物数据' >/dev/null
adb exec-out screencap -p > "$SCREENSHOTS/data-management.png"

for file in "$SCREENSHOTS"/*.png; do
  test -s "$file"
  echo "CAPTURED: $file"
  sha256sum "$file"
done

# Run all native integration suites in one runner session, including the
# actual PCM MethodChannel sink. A single invocation avoids repeated
 # XCTest/VM service attach cycles and bounds the total integration time.
# Run text and character-speech integration against the real FastAPI routes.
# Use a temporary mock ledger, a synthetic token and role-specific test tones.
export PERSON_GATEWAY_TOKEN="$(python -c 'import secrets; print(secrets.token_hex(24))')"
export PERSON_GATEWAY_CHARACTERS=star,moon PERSON_GATEWAY_MODE=mock PERSON_VOICE_MODE=demo PERSON_ASR_MODE=demo
export PERSON_GATEWAY_LEDGER="$(mktemp -d)/requests.sqlite"
python "$ROOT/services/person_gateway/gateway.py" &
gateway_pid=$!
for _ in {1..30}; do
  if curl -fsS http://127.0.0.1:8788/health >/dev/null; then break; fi
  sleep 1
done
curl -fsS http://127.0.0.1:8788/health >/dev/null
adb -s "$ANDROID_SERIAL" reverse tcp:8788 tcp:8788
timeout --signal=TERM --kill-after=10s 900s flutter test integration_test -d "$ANDROID_SERIAL" \
  --dart-define=VOICE_TEST_URL=http://127.0.0.1:8788 \
  --dart-define=VOICE_TEST_TOKEN="$PERSON_GATEWAY_TOKEN" --reporter expanded --timeout 5m
