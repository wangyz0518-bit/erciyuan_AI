#!/usr/bin/env bash
# #41 admission tests with a fake ADB executable. These are NOT device tests.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TARGET="$ROOT/apps/mobile/tool/run_android_physical_acceptance.sh"
MOCK_BIN="$(mktemp -d)"
trap 'rm -rf "$MOCK_BIN"' EXIT

cat > "$MOCK_BIN/adb" <<'ADB'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == "-s" ]]; then
  shift 2
fi
case "${1:-}" in
  get-state)
    printf '%s\n' "${FAKE_ADB_STATE-device}"
    ;;
  shell)
    if [[ "${2:-}" == "getprop" && "${3:-}" == "ro.kernel.qemu" ]]; then
      printf '%s\n' "${FAKE_ADB_QEMU:-0}"
    fi
    ;;
  devices)
    printf 'List of devices attached\n'
    ;;
  *)
    exit 91
    ;;
esac
ADB
cat > "$MOCK_BIN/flutter" <<'FLUTTER'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "Flutter should never run for rejected ADB targets" >&2
exit 97
FLUTTER
chmod +x "$MOCK_BIN/adb" "$MOCK_BIN/flutter"

expect_rejection() {
  local label="$1" expected="$2" serial="$3" state="$4" qemu="$5"
  local status=0 output=""
  output="$(env PATH="$MOCK_BIN:$PATH" ANDROID_SERIAL="$serial" \
    FAKE_ADB_STATE="$state" FAKE_ADB_QEMU="$qemu" \
    bash "$TARGET" 2>&1)" || status=$?
  if [[ "$status" -ne 2 || "$output" != *"$expected"* ||
        "$output" == *"Flutter should never run"* ]]; then
    echo "FAIL: $label (status=$status, output=$output)" >&2
    return 1
  fi
  echo "PASS: $label (rejected before Flutter)"
}

expect_rejection "explicit offline device" "not connected and authorized" "device-123" "offline" "0"
expect_rejection "explicit unauthorized device" "not connected and authorized" "device-123" "unauthorized" "0"
expect_rejection "missing ADB serial" "not connected and authorized" "missing-device" "" "0"
expect_rejection "emulator-serial" "Refusing Android emulator" "emulator-5554" "device" "1"
expect_rejection "emulator behind nonstandard serial" "Refusing Android emulator" "device-123" "device" "1"

echo "Only rejection paths were tested. No physical device, APK, or SQLite test was executed."
