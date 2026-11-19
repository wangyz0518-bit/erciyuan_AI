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
sleep 12
adb shell pidof dev.erciyuan.mobile >/dev/null
adb exec-out screencap -p > "$SCREENSHOTS/person-home.png"

# Coordinates are fixed because CI forces a 375x812, 160dpi device.
# The selected character's "continue chat" button is below both cards.
adb shell input tap 190 458
sleep 4
adb shell pidof dev.erciyuan.mobile >/dev/null
adb exec-out screencap -p > "$SCREENSHOTS/continuous-chat.png"

if cmp -s "$SCREENSHOTS/person-home.png" "$SCREENSHOTS/continuous-chat.png"; then
  echo "ERROR: Chat screenshot matches the home image; navigation did not occur." >&2
  exit 1
fi

adb shell input keyevent KEYCODE_BACK
sleep 2
adb shell input tap 350 55
sleep 3
adb exec-out screencap -p > "$SCREENSHOTS/data-management.png"

if cmp -s "$SCREENSHOTS/person-home.png" "$SCREENSHOTS/data-management.png"; then
  echo "ERROR: Data management screenshot matches the home image." >&2
  exit 1
fi

for file in "$SCREENSHOTS"/*.png; do
  test -s "$file"
  echo "CAPTURED: $file"
  sha256sum "$file"
done

# Run all native integration suites in one runner session, including the
# actual PCM MethodChannel sink. A single invocation avoids repeated
 # XCTest/VM service attach cycles and bounds the total integration time.
timeout --signal=TERM --kill-after=10s 900s flutter test integration_test -d "$ANDROID_SERIAL" --reporter expanded --timeout 5m
