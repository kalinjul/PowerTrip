#!/usr/bin/env bash
#
# Reads changed paths, one per line, and prints which sides they touch:
# "android", "ios", "android ios", or nothing.
#
#   git diff --name-only "$(git merge-base origin/main HEAD)" | tools/changed-sides.sh
#
# Shared code that both apps build on wakes both; a path no rule knows wakes
# both too, so a new module is checked until someone sorts it in here.
set -euo pipefail

android=false
ios=false

while IFS= read -r path; do
  case "$path" in
    "") ;;
    *.md|docs/*|.claude/*|LICENSE*|.gitignore) ;;
    iosApp/*|shared/src/iosMain/*|shared/src/iosTest/*|tools/ios-*|tools/check-swift.sh|.github/workflows/ios-goldens.yml) ios=true ;;
    phone-ui/*|ui-tests/*|androidApp/*|shared/src/androidMain/*|shared/src/jvmMain/*|shared/src/jvmTest/*|tools/screenshots.sh|.github/workflows/release.yml) android=true ;;
    *) android=true; ios=true ;;
  esac
done

sides=()
if $android; then sides+=(android); fi
if $ios; then sides+=(ios); fi
echo "${sides[*]+"${sides[*]}"}"
