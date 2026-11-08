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
python3 - <<'PYTHON'
import os
from pathlib import Path
import subprocess
import sys
import tempfile

process = subprocess.Popen([".build/runtime-tests", "--self-test"], env=dict(os.environ, NSUnbufferedIO="YES"))
try:
    result = process.wait(timeout=30)
except subprocess.TimeoutExpired:
    print("[runtime] Tests exceeded 30s; sampling the test process without skipping or stopping tests", flush=True)
    with tempfile.TemporaryDirectory(prefix="Neylu-runtime-stack-") as folder:
        trace = Path(folder) / "sample.txt"
        try:
            subprocess.run(["/usr/bin/sample", str(process.pid), "1", "10", "-file", str(trace)], timeout=15, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            print("[runtime] Stack sampling unavailable: " + str(error), flush=True)
        if trace.exists():
            print(trace.read_text(errors="replace"), flush=True)
    result = process.wait()
sys.exit(result)
PYTHON
