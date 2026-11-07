#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/UpdateModuleCache
xcrun swiftc -module-cache-path "$PWD/.build/UpdateModuleCache" -swift-version 5 -O \
  -target "$(uname -m)-apple-macosx13.0" Sources/Localization.swift Sources/UpdateCore.swift Sources/UpdateMessages.swift Sources/Updates.swift \
  Tests/Updates/main.swift -framework AppKit -framework Security -o .build/update-tests
.build/update-tests "$PWD/build/Neylu.app" "$@"

# Requires an active macOS GUI session; unit and signature tests above run in CI.
for argument in "$@"; do
  if [[ "$argument" == --integration ]]; then
    python3 Tests/Updates/helper_integration.py
  fi
done
