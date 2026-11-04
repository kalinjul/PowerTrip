#!/usr/bin/env bash
#
# Pins which side's gates a changed path wakes up: tools/changed-sides.test.sh
set -euo pipefail

SCRIPT="$(dirname "${BASH_SOURCE[0]}")/changed-sides.sh"
failures=0

expect() {
  local want="$1"; shift
  local got
  got="$(printf '%s\n' "$@" | "$SCRIPT")"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $* -> '$got', want '$want'"
    failures=$((failures + 1))
  fi
}

expect "ios" iosApp/PowerTrip/Phone/GarageView.swift
expect "ios" shared/src/iosMain/kotlin/X.kt
expect "ios" shared/src/iosTest/kotlin/XTest.kt
expect "ios" tools/ios-sim.sh tools/check-swift.sh
expect "android" phone-ui/src/main/kotlin/X.kt
expect "android" ui-tests/src/test/kotlin/XTest.kt
expect "android" androidApp/src/main/AndroidManifest.xml
expect "android" shared/src/androidMain/kotlin/X.kt
expect "android" shared/src/jvmMain/kotlin/X.kt shared/src/jvmTest/kotlin/XTest.kt
expect "android" tools/screenshots.sh
expect "ios" .github/workflows/ios-goldens.yml
expect "android ios" shared/src/commonMain/kotlin/X.kt
expect "android ios" shared/src/commonMain/composeResources/values-de/strings.xml
expect "android ios" shared/src/commonTest/kotlin/XTest.kt
expect "android ios" shared/build.gradle.kts
expect "android ios" gradle/libs.versions.toml settings.gradle.kts build.gradle.kts gradle.properties
expect "android ios" .github/workflows/ci.yml
expect "android ios" tools/check.sh
expect "android ios" iosApp/X.swift phone-ui/src/main/kotlin/X.kt
# Somewhere nobody thought of: both, rather than nothing.
expect "android ios" some-new-module/src/X.kt
expect "" docs/testing.md README.md AGENTS.md .claude/skills/durchziehen/SKILL.md
expect "" iosApp/README.md
expect "" ""

if [ "$failures" -gt 0 ]; then
  echo "$failures failing"
  exit 1
fi
echo "changed-sides: all pass"
