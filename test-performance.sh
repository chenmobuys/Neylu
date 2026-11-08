#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source scripts/swift-sources.sh
mkdir -p .build/PerformanceModuleCache
xcrun swiftc -module-cache-path "$PWD/.build/PerformanceModuleCache" -swift-version 5 -Osize -whole-module-optimization \
  -target "$(uname -m)-apple-macosx12.0" "${neylu_sources[@]}" Tests/Performance/main.swift \
  -o .build/performance-tests -framework AppKit -framework SwiftUI -framework Carbon -framework SystemConfiguration \
  -framework ServiceManagement -framework IOKit -framework DiskArbitration -lsqlite3
.build/performance-tests "$@"
