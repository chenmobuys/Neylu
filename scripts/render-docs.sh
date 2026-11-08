#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
docs_destination="${1:-$PWD/docs/images}"
if [ "$#" -gt 0 ]; then shift; fi
mkdir -p .build/docs-renderer .build/ModuleCache
# shellcheck source=scripts/swift-sources.sh
source scripts/swift-sources.sh
cp scripts/render-docs.swift .build/docs-renderer/main.swift
xcrun swiftc -module-cache-path "$PWD/.build/ModuleCache" -swift-version 5 -O -D NEYLU_PREVIEW \
  "${neylu_sources[@]}" Tests/Support/ScreenshotFixtures.swift \
  .build/docs-renderer/main.swift -o .build/docs-renderer/render \
  -framework AppKit -framework SwiftUI -framework Carbon -framework SystemConfiguration -framework ServiceManagement \
  -framework IOKit -framework DiskArbitration -lsqlite3
.build/docs-renderer/render "$docs_destination" "$@"
