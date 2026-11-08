#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=scripts/swift-sources.sh
source scripts/swift-sources.sh
mkdir -p .build/RuntimeModuleCache
runtime_compile_started=$SECONDS
echo "[runtime] Compiling native regression executable ($(uname -m))"
xcrun swiftc -module-cache-path "$PWD/.build/RuntimeModuleCache" -swift-version 5 -Osize -whole-module-optimization \
  -target "$(uname -m)-apple-macosx12.0" "${neylu_sources[@]}" Tests/Runtime/main.swift \
  -o .build/runtime-tests -framework AppKit -framework SwiftUI -framework Carbon -framework SystemConfiguration \
  -framework ServiceManagement -framework IOKit -framework DiskArbitration -lsqlite3
echo "[runtime] Compilation completed in $((SECONDS - runtime_compile_started))s; starting tests"
NSUnbufferedIO=YES .build/runtime-tests --self-test
