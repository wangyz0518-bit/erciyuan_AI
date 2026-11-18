#!/usr/bin/env bash
# Runs only in the ephemeral Android emulator CI environment.
set -euo pipefail

if [[ ! -f pubspec.yaml || ! -f integration_test/acceptance_test.dart || ! -f integration_test/storage_failure_test.dart ]]; then
  echo "Expected Flutter PoC root (apps/mobile_poc) as working directory" >&2
  exit 2
fi

if [[ -z "${GITHUB_WORKSPACE:-}" ]]; then
  echo "GITHUB_WORKSPACE is required for this CI helper" >&2
  exit 2
fi

# Capture logs only after the tests exit, even if one fails. Do not upload
# recordings, databases, or app-private files. Android logcat is diagnostic.
trap 'adb -s emulator-5554 logcat -d > "$GITHUB_WORKSPACE/android-emulator-logcat.txt" || true' EXIT

echo "Running emulator integration tests from: $PWD"
flutter devices
flutter test integration_test/acceptance_test.dart -d emulator-5554 --reporter expanded
flutter test integration_test/storage_failure_test.dart -d emulator-5554 --reporter expanded
