#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/UpdateModuleCache
fixture_directory="$(mktemp -d "${TMPDIR:-/tmp}/Neylu-appcast-test.XXXXXX")"
trap 'rm -rf "$fixture_directory"' EXIT
python3 Tests/Updates/appcast_fixture.py "$fixture_directory"
xcrun swiftc -module-cache-path "$PWD/.build/UpdateModuleCache" -swift-version 5 -O \
  -target "$(uname -m)-apple-macosx12.0" Sources/Localization.swift Sources/UpdateCore.swift Sources/UpdateMessages.swift Sources/ReleaseNotes.swift Sources/Appcast.swift Sources/UpdateDiscovery.swift Sources/Updates.swift \
  Tests/Updates/main.swift -framework AppKit -framework Security -o .build/update-tests
NEYLU_APPCAST_FIXTURES="$fixture_directory" .build/update-tests "$PWD/build/Neylu.app" "$@"

# Requires an active macOS GUI session; unit and signature tests above run in CI.
for argument in "$@"; do
  if [[ "$argument" == --integration ]]; then
    python3 Tests/Updates/helper_integration.py
  fi
done
