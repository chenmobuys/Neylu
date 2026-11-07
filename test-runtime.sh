#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=scripts/swift-sources.sh
source scripts/swift-sources.sh
mkdir -p .build/RuntimeModuleCache
xcrun swiftc -module-cache-path "$PWD/.build/RuntimeModuleCache" -swift-version 5 -Osize -whole-module-optimization \
  -target "$(uname -m)-apple-macosx13.0" "${neylu_sources[@]}" Tests/Runtime/main.swift \
  -o .build/runtime-tests -framework AppKit -framework SwiftUI -framework SystemConfiguration \
  -framework ServiceManagement -framework IOKit -framework DiskArbitration -lsqlite3
.build/runtime-tests --self-test
