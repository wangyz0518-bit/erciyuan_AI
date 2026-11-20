#!/usr/bin/env bash
# #41: run the official UI and SQLite acceptance on an explicitly connected
# physical Android phone. Never accepts an emulator as a substitute.
# Run locally with an unlocked USB-debugging-enabled phone:
#   ANDROID_SERIAL=<serial> bash apps/mobile/tool/run_android_physical_acceptance.sh
set -Eeuo pipefail

command -v adb >/dev/null || { echo "adb is required" >&2; exit 2; }
command -v flutter >/dev/null || { echo "Flutter SDK is required" >&2; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT/apps/mobile"

SERIAL="${ANDROID_SERIAL:-}"
if [[ -z "$SERIAL" ]]; then
  SERIAL="$(adb devices -l | awk 'NR > 1 && $2 == "device" && $1 !~ /^emulator-/ { print $1; exit }')"
fi
if [[ -z "$SERIAL" ]]; then
  echo "No authorized physical Android device found. Connect and unlock a USB-debugging-enabled phone." >&2
  exit 2
fi
# Explicit ANDROID_SERIAL must not bypass ADB authorization. An offline or
# unauthorized serial should fail *before* a Flutter build is started.
ADB_STATE="$(adb -s "$SERIAL" get-state 2>/dev/null || true)"
if [[ "$ADB_STATE" != "device" ]]; then
  echo "ADB serial is not connected and authorized (state: ${ADB_STATE:-unavailable})." >&2
  exit 2
fi
if [[ "$SERIAL" == emulator-* ]] ||
   [[ "$(adb -s "$SERIAL" shell getprop ro.kernel.qemu | tr -d '\r')" == "1" ]]; then
  echo "Refusing Android emulator as #41 physical-device evidence." >&2
  exit 2
fi

for file in integration_test/acceptance_test.dart integration_test/storage_failure_test.dart; do
  if [[ ! -f "$file" ]]; then
    echo "Official test '$file' is missing. Merge the verified #37 implementation first." >&2
    exit 2
  fi
done

# Keep all diagnostic files outside the public Git repository by default.
REPORT_DIR="${ERCIYUAN_REPORT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/erciyuan-physical-XXXXXXXX")}"
mkdir -p "$REPORT_DIR"
echo "Local-only report directory: $REPORT_DIR"

MODEL="$(adb -s "$SERIAL" shell getprop ro.product.model | tr -d '\r')"
RELEASE="$(adb -s "$SERIAL" shell getprop ro.build.version.release | tr -d '\r')"
SDK="$(adb -s "$SERIAL" shell getprop ro.build.version.sdk | tr -d '\r')"
{
  echo "Git revision: $(git rev-parse HEAD)"
  echo "Android model: $MODEL"
  echo "Android release: $RELEASE (API $SDK)"
  echo "Device type: physical (ro.kernel.qemu != 1)"
  echo "Run: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "Native Chinese keyboard, real background transition, safe-area and hardware speaker quality are manual tests; not validated by tester.enterText"
} > "$REPORT_DIR/device-build.txt"

collect_failure() {
  local result=$?
  if [[ "$result" -ne 0 ]]; then
    adb -s "$SERIAL" exec-out screencap -p > "$REPORT_DIR/failure-screen.png" || true
    adb -s "$SERIAL" logcat -d -s flutter:* AndroidRuntime:E \
      > "$REPORT_DIR/filtered-app-logcat.txt" || true
    echo "Physical-device test failed (exit $result). Local report: $REPORT_DIR" >&2
  fi
}
trap collect_failure EXIT

flutter pub get
flutter build apk --debug
adb -s "$SERIAL" install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s "$SERIAL" shell am force-stop dev.erciyuan.mobile || true
adb -s "$SERIAL" shell am start -n dev.erciyuan.mobile/.MainActivity
sleep 8
adb -s "$SERIAL" shell pidof dev.erciyuan.mobile >/dev/null
adb -s "$SERIAL" exec-out screencap -p > "$REPORT_DIR/official-home.png"
test -s "$REPORT_DIR/official-home.png"

flutter test integration_test/acceptance_test.dart -d "$SERIAL" --reporter expanded
flutter test integration_test/storage_failure_test.dart -d "$SERIAL" --reporter expanded

cat > "$REPORT_DIR/manual-device-checklist.md" <<'CHECKLIST'
# Device-specific manual acceptance (not automatically verified)

- [ ] Enter and send Chinese text using the **real Android IME**
- [ ] Open and close the keyboard; no overlap/hidden composer at common font scaling
- [ ] Android system Back and gesture Back return to the expected person home
- [ ] Change characters and confirm per-character chat history, including after force-stop/relaunch
- [ ] Rotate / change accessibility font scale; check display cutouts and gesture insets
- [ ] Background and foreground the app; verify no lost history, crashes or duplicate turns
- [ ] Test permission refusal/revocation where the current feature actually uses that permission
- [ ] Confirm model, Android release, APK revision, manual tester, date and any device-specific defects

These items require a human with a connected physical phone. Do not mark them
passed merely because Flutter integration_test and Android emulator CI passed.
CHECKLIST

echo "Automated integration checks completed on a physical Android device."
echo "Manual checklist remains outstanding: $REPORT_DIR/manual-device-checklist.md"
