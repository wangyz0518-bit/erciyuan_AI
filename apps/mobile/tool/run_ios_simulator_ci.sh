#!/usr/bin/env bash
# #40: real hosted macOS/Xcode iOS Simulator build, install, launch and UI test.
# No Apple signing, physical device, paid API, or production model credentials.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT/apps/mobile"
ARTIFACTS="$ROOT/artifacts/official-ios-simulator"
mkdir -p "$ARTIFACTS"

# Integration-test sharding.
#
# `flutter test integration_test` rebuilds the app once per test file -- each
# file is its own entrypoint -- so the suite list spends far more time inside
# Xcode than inside test code. On the 2026-11-22 run, eight suites burned 635 s
# of `Xcode build` against roughly 140 s of actual assertions, and the eight
# builds plus boot overhead did not fit in the old 20-minute safety net.
#
# IOS_INTEGRATION_SHARD=<index>/<count> runs the index-th round-robin slice of
# the sorted suite list, so CI can spread the suites over parallel jobs.
# Unset, or "0/1", keeps the previous behaviour: every suite in one job.
SHARD_SPEC="${IOS_INTEGRATION_SHARD:-0/1}"
SHARD_INDEX="${SHARD_SPEC%%/*}"
SHARD_COUNT="${SHARD_SPEC##*/}"
case "$SHARD_INDEX" in
  '' | *[!0-9]*) echo "IOS_INTEGRATION_SHARD index must be a number, got '$SHARD_INDEX'" >&2; exit 2 ;;
esac
case "$SHARD_COUNT" in
  '' | *[!0-9]*) echo "IOS_INTEGRATION_SHARD count must be a number, got '$SHARD_COUNT'" >&2; exit 2 ;;
esac
if [[ "$SHARD_COUNT" -lt 1 || "$SHARD_INDEX" -ge "$SHARD_COUNT" ]]; then
  echo "IOS_INTEGRATION_SHARD '$SHARD_SPEC' needs 0 <= index < count" >&2
  exit 2
fi

# Only one shard performs the build/install/launch/screenshot smoke test, so
# the parallel jobs do not race to install the same bundle on their own
# simulators for no extra coverage. Override with IOS_RUN_UI_SMOKE=0|1.
RUN_UI_SMOKE="${IOS_RUN_UI_SMOKE:-}"
if [[ -z "$RUN_UI_SMOKE" ]]; then
  if [[ "$SHARD_INDEX" -eq 0 ]]; then RUN_UI_SMOKE=1; else RUN_UI_SMOKE=0; fi
fi

# Whole-shard budget. Deliberately generous: it exists to turn a wedged run
# into a readable failure well before the job's own timeout-minutes (60), not
# to predict the expected duration. A shard of 3 suites finishes in minutes
# once the app is built; anything approaching this bound is hung, not slow.
INTEGRATION_TIMEOUT_MIN="${IOS_INTEGRATION_TIMEOUT_MIN:-30}"

xcodebuild -version
xcrun simctl list devices available

# The ONNX Runtime binary target is vendored from NuGet because its upstream CDN
# is retired. Idempotent: a no-op when the xcframework is already in place, so
# this works both on a warm cache and on a clean checkout.
python3 tool/fetch_onnxruntime_ios.py

APP="build/ios/iphonesimulator/Runner.app"
BUNDLE_ID=""

if [[ "$RUN_UI_SMOKE" == "1" ]]; then
  flutter build ios --simulator --debug --no-codesign
  test -d "$APP"
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
  test -n "$BUNDLE_ID"
fi

# Choose an installed iPhone simulator, not an unavailable placeholder.
#
# `devices[0]` is not good enough: the runtime list is unordered with respect
# to form factor, and a host with an unusual device first (a foldable, a
# largest-screen model) fails layout assertions such as RenderFlex overflow
# that have nothing to do with the code under test. Set IOS_SIMULATOR_NAME to
# pin an exact device name when a machine needs it.
SIM_ID="$(IOS_SIMULATOR_NAME="${IOS_SIMULATOR_NAME:-}" xcrun simctl list devices available -j | python3 -c '
import json
import os
import re
import sys

wanted = os.environ.get("IOS_SIMULATOR_NAME", "").strip()
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

if wanted:
    exact = [item for item in devices if item.get("name") == wanted]
    if not exact:
        names = ", ".join(sorted({item.get("name", "") for item in devices}))
        raise SystemExit(f"IOS_SIMULATOR_NAME={wanted!r} not found. Available: {names}")
    print(exact[0]["udid"])
    raise SystemExit(0)

# Prefer a plain phone-shaped iPhone: a numeric generation with the shortest
# name wins, so "iPhone 18" beats "iPhone 18 Pro Max" and a concept device
# such as "iPhone Duo" (no generation number) sorts last. That mirrors what CI
# images ship as the default phone, and it avoids the foldable/large-screen
# layouts that trip unrelated overflow assertions on developer machines.
def rank(item):
    name = item.get("name", "")
    match = re.match(r"^iPhone (\d+)(?: (\w+))?$", name)
    if not match:
        return (2, 0, name)
    has_suffix = 1 if match.group(2) else 0
    return (0 if not has_suffix else 1, int(match.group(1)), name)

devices.sort(key=rank)
print(devices[0]["udid"])
')"
echo "Using iOS Simulator: $SIM_ID"
echo "$SIM_ID" > "$ARTIFACTS/simulator-udid.txt"

if ! xcrun simctl list devices | grep -F "$SIM_ID" | grep -q '(Booted)'; then
  xcrun simctl boot "$SIM_ID"
fi
xcrun simctl bootstatus "$SIM_ID" -b

if [[ "$RUN_UI_SMOKE" == "1" ]]; then
  xcrun simctl install "$SIM_ID" "$APP"
  xcrun simctl launch "$SIM_ID" "$BUNDLE_ID"
  sleep 10
  xcrun simctl io "$SIM_ID" screenshot "$ARTIFACTS/ios-person-home.png"
  test -s "$ARTIFACTS/ios-person-home.png"
else
  echo "NOTICE: shard $SHARD_INDEX/$SHARD_COUNT skips the UI smoke test; shard 0 covers it"
fi

# The iOS simulator must run the formal same SQLite+UI acceptance where
# present. On a base revision predating #37, record the missing suite;
# #40 cannot be closed until the post-#37 integration run actually succeeds.
if [[ ! -f integration_test/acceptance_test.dart ]]; then
  echo "NOTICE: official integration tests are absent on this baseline; simulator launch only is verified"
else
  # PR #70: keep every suite of a shard inside a *single* `flutter test`
  # process. A second process against the same booted simulator can leave the
  # XCTest/VM service attach waiting indefinitely after the first suite.
  #
  # The suite files are ordered so that a shard is a stable, reproducible
  # slice: `sort` then round-robin, which keeps each shard's build/test mix
  # balanced instead of handing all the slow suites to one job.
  SUITES=()
  while IFS= read -r suite; do
    [[ -n "$suite" ]] && SUITES+=("$suite")
  done < <(python3 - "$SHARD_INDEX" "$SHARD_COUNT" <<'PY'
import os
import sys

index, count = int(sys.argv[1]), int(sys.argv[2])
names = sorted(
    name for name in os.listdir("integration_test") if name.endswith("_test.dart")
)
for name in names[index::count]:
    print(os.path.join("integration_test", name))
PY
)

  if [[ "${#SUITES[@]}" -eq 0 ]]; then
    echo "NOTICE: shard $SHARD_INDEX/$SHARD_COUNT has no suites; nothing to run"
  else
    echo "Shard $SHARD_INDEX/$SHARD_COUNT runs ${#SUITES[@]} suite(s):"
    printf '  %s\n' "${SUITES[@]}"
    SIM_ID="$SIM_ID" \
      IOS_INTEGRATION_TIMEOUT_MIN="$INTEGRATION_TIMEOUT_MIN" \
      python3 - "${SUITES[@]}" <<'PY'
import os
import subprocess
import sys
import time

command = [
    "flutter",
    "test",
    *sys.argv[1:],
    "-d",
    os.environ["SIM_ID"],
    "--reporter",
    "expanded",
    "--timeout",
    "5m",
]
budget = int(os.environ["IOS_INTEGRATION_TIMEOUT_MIN"]) * 60
started = time.monotonic()
print(f"Running {len(sys.argv) - 1} suite(s), budget {budget // 60} min", flush=True)
try:
    subprocess.run(command, check=True, timeout=budget)
except subprocess.TimeoutExpired:
    elapsed = time.monotonic() - started
    raise SystemExit(
        f"iOS integration shard exceeded the {budget // 60}-minute safety "
        f"timeout after {elapsed:.0f}s of test execution. Raise "
        f"IOS_INTEGRATION_TIMEOUT_MIN or split IOS_INTEGRATION_SHARD further "
        f"if the suites genuinely need more than that."
    )
PY
  fi
fi

if [[ "$RUN_UI_SMOKE" == "1" ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARTIFACTS/Runner-ios-simulator.zip"
  test -s "$ARTIFACTS/Runner-ios-simulator.zip"
fi