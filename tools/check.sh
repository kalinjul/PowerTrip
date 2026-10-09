#!/usr/bin/env bash
#
# The quality gates, for the side a change touches, the same ones CI runs.
#
#   tools/check.sh                  # the sides changed since main (committed or not)
#   tools/check.sh android|ios|all  # one side, or both, regardless of the diff
#   tools/check.sh sides            # only print which sides changed
#   --no-goldens                    # skip the screenshot comparison (durchziehen's inner loop)
#   --record                        # re-record the goldens of the chosen sides, then validate
#   --base <ref>                    # compare against another ref than origin/main
#
# Android: every module compiles, shared/phone/car tests, goldens in the
# container (tools/screenshots.sh). iOS: Kotlin/Native tests, the app and its
# test bundles build, snapshot goldens on the pinned simulator, and the
# XCUITest when iosApp/Secrets.xcconfig is there (it talks to the backend).
# Without Xcode, iOS falls back to what Linux can check and says what it skipped.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$REPO_ROOT/iosApp"
CHECK_DIR="$IOS_DIR/build/check"
STUDIO_JDK="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
# shellcheck source=ios-toolchain.env
. "$REPO_ROOT/tools/ios-toolchain.env"

die() { echo "$*" >&2; exit 1; }
step() { echo; echo "== $*"; }

goldens=true
record=false
base=""
target="auto"
while [ $# -gt 0 ]; do
  case "$1" in
    --no-goldens) goldens=false ;;
    --record) record=true ;;
    --base) base="${2:?--base needs a ref}"; shift ;;
    auto|android|ios|all|sides) target="$1" ;;
    *) die "usage: $0 [auto|android|ios|all|sides] [--no-goldens] [--record] [--base <ref>]" ;;
  esac
  shift
done
if $record && ! $goldens; then die "--record and --no-goldens contradict each other"; fi

changed_sides() {
  local ref="$base"
  if [ -z "$ref" ]; then
    if git -C "$REPO_ROOT" rev-parse -q --verify origin/main >/dev/null; then ref=origin/main; else ref=main; fi
  fi
  local fork
  fork="$(git -C "$REPO_ROOT" merge-base "$ref" HEAD)" || die "no common history with $ref"
  {
    git -C "$REPO_ROOT" diff --name-only "$fork"
    git -C "$REPO_ROOT" ls-files --others --exclude-standard
  } | "$REPO_ROOT/tools/changed-sides.sh"
}

case "$target" in
  sides) changed_sides; exit 0 ;;
  auto) sides="$(changed_sides)" ;;
  all) sides="android ios" ;;
  *) sides="$target" ;;
esac

if [ -z "$sides" ]; then
  echo "Nothing either app builds on changed; no gates to run."
  exit 0
fi
echo "Gates for: $sides"

if [ -z "${JAVA_HOME:-}" ] && [ -d "$STUDIO_JDK" ]; then export JAVA_HOME="$STUDIO_JDK"; fi
gradle() { (cd "$REPO_ROOT" && ./gradlew --console=plain --no-scan "$@"); }

android_gates() {
  step "Android: compile every module, shared, phone and car tests"
  gradle :shared:compileKotlinJvm :phone-ui:compileDebugKotlin :androidApp:compileDebugKotlin \
    :ui-tests:compileDebugUnitTestKotlin :ui-tests:compileDebugScreenshotTestKotlin \
    :shared:jvmTest :ui-tests:testDebugUnitTest :androidApp:testDebugUnitTest
  if $record; then
    step "Android: re-record goldens"
    "$REPO_ROOT/tools/screenshots.sh" update
  fi
  if $goldens; then
    step "Android: goldens"
    "$REPO_ROOT/tools/screenshots.sh" validate
  fi
}

# The pinned Xcode, or a side-by-side install of it the way CI runners have them.
select_xcode() {
  local have
  have="$(xcodebuild -version | sed -n 's/^Xcode //p')"
  [ "$have" = "$XCODE_VERSION" ] && return
  local pinned="/Applications/Xcode_$XCODE_VERSION.app/Contents/Developer"
  if [ -d "$pinned" ]; then
    export DEVELOPER_DIR="$pinned"
    return
  fi
  die "the iOS gates are pinned to Xcode $XCODE_VERSION, this machine has $have (tools/ios-toolchain.env)"
}

# Its own simulator, so the gates never touch the one a developer is using.
check_simulator() {
  local runtime="com.apple.CoreSimulator.SimRuntime.iOS-${IOS_RUNTIME//./-}"
  local runtimes
  runtimes="$(xcrun simctl list runtimes -j)"
  case "$runtimes" in
    *"\"$runtime\""*) ;;
    *)
      $goldens && die "the iOS $IOS_RUNTIME simulator is missing: xcodebuild -downloadPlatform iOS -buildVersion $IOS_RUNTIME"
      runtime="$(python3 -c '
import json, sys
ios = [r["identifier"] for r in json.loads(sys.argv[1])["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
print(sorted(ios, key=lambda r: [int(n) for n in r.rsplit("iOS-", 1)[1].split("-")])[-1] if ios else "")
' "$runtimes")"
      [ -n "$runtime" ] || die "no iOS simulator installed: xcodebuild -downloadPlatform iOS"
      ;;
  esac
  local udid
  udid="$(xcrun simctl list devices -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"].get(sys.argv[1], [])
print(next((d["udid"] for d in devices if d["name"] == sys.argv[2] and d["isAvailable"]), ""))
' "$runtime" "$CHECK_SIMULATOR")"
  if [ -z "$udid" ]; then
    local type="com.apple.CoreSimulator.SimDeviceType.${IOS_DEVICE// /-}"
    udid="$(xcrun simctl create "$CHECK_SIMULATOR" "$type" "$runtime")"
  fi
  echo "$udid"
}

ios_linux_gates() {
  step "iOS without Xcode: iosMain compiles, Swift parses"
  gradle :shared:compileKotlinIosSimulatorArm64
  local swift=0
  "$REPO_ROOT/tools/check-swift.sh" || swift=$?
  if [ "$swift" -eq 127 ]; then
    echo "Swift syntax unchecked: no swiftc on this machine."
  elif [ "$swift" -ne 0 ]; then
    exit "$swift"
  fi
  echo
  echo "iOS app build, snapshot goldens and UI tests skipped: no Xcode on this machine. CI checks them."
}

ios_gates() {
  # A Mac with only the Command Line Tools has an xcodebuild that refuses to run.
  if [ "$(uname)" != Darwin ] || ! xcodebuild -version >/dev/null 2>&1; then
    ios_linux_gates
    return
  fi
  # Only the goldens depend on the pin; the build and tests run on any Xcode.
  if $goldens; then select_xcode; else echo "Xcode $(xcodebuild -version | sed -n 's/^Xcode //p'), unpinned: no goldens"; fi
  command -v xcodegen >/dev/null || die "xcodegen missing: brew install xcodegen"

  step "iOS: shared tests on Kotlin/Native"
  gradle :shared:iosSimulatorArm64Test

  step "iOS: app and test bundles build"
  local udid
  udid="$(check_simulator)"
  # A simulator still booting refuses to launch the test runner ("failed preflight checks").
  xcrun simctl bootstatus "$udid" -b >/dev/null
  (cd "$IOS_DIR" && xcodegen generate --quiet)
  local xcode=(-project "$IOS_DIR/ChargeAhead.xcodeproj" -scheme ChargeAhead
    -destination "id=$udid" -derivedDataPath "$CHECK_DIR/derived" -quiet)
  local jdk=()
  if [ -n "${JAVA_HOME:-}" ]; then jdk=("JAVA_HOME=$JAVA_HOME"); fi
  xcodebuild build-for-testing "${xcode[@]}" ${jdk[@]+"${jdk[@]}"}

  # The goldens are German, like Android's.
  local run=(test-without-building "${xcode[@]}" -testLanguage de -testRegion DE)
  if $record; then
    step "iOS: re-record goldens"
    # Renamed or deleted tests would otherwise leave their goldens behind.
    rm -rf "$IOS_DIR/ChargeAheadSnapshotTests/__Snapshots__"
    # Recording fails every test on purpose ("record mode is on"); the validate run below is the verdict.
    TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all \
      xcodebuild "${run[@]}" -only-testing:ChargeAheadSnapshotTests || true
  fi
  if $goldens; then
    step "iOS: goldens on $CHECK_SIMULATOR (iOS $IOS_RUNTIME)"
    rm -rf "$CHECK_DIR/snapshot-failures"
    TEST_RUNNER_SNAPSHOT_TESTING_RECORD=never \
      TEST_RUNNER_SNAPSHOT_ARTIFACTS="$CHECK_DIR/snapshot-failures" \
      xcodebuild "${run[@]}" -only-testing:ChargeAheadSnapshotTests \
      -resultBundlePath "$CHECK_DIR/snapshots-$(date +%s).xcresult" \
      || die "snapshot tests failed; differing renders, if any, are in $CHECK_DIR/snapshot-failures"
  fi

  if [ -f "$IOS_DIR/Secrets.xcconfig" ] && [ -z "${CI:-}" ]; then
    step "iOS: UI tests (against the backend)"
    # A fresh install: the tests start from an empty garage.
    xcrun simctl uninstall "$udid" org.julakali.chargeahead 2>/dev/null || true
    xcrun simctl privacy "$udid" grant location org.julakali.chargeahead
    # Planning starts from the current position; Hamburg, like the Android previews.
    xcrun simctl location "$udid" set 53.5511,9.9937
    TEST_RUNNER_SCREENSHOT_DIR="$CHECK_DIR/uitest-screenshots" \
      xcodebuild "${run[@]}" -only-testing:ChargeAheadUITests
  else
    echo
    echo "iOS UI tests skipped: they need the backend from iosApp/Secrets.xcconfig, which CI does not have."
  fi
}

for side in $sides; do
  case "$side" in
    android) android_gates ;;
    ios) ios_gates ;;
  esac
done
echo
echo "Gates passed for: $sides"
