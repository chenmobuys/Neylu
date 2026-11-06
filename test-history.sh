#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/HistoryModuleCache
xcrun swiftc -module-cache-path "$PWD/.build/HistoryModuleCache" -swift-version 5 -O \
  -target arm64-apple-macosx13.0 Sources/History.swift Tests/main.swift -lsqlite3 -o .build/history-tests
.build/history-tests
