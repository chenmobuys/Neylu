#!/bin/bash
# Swift Testing remains the test runner; this wrapper only monitors its process.
set -euo pipefail
cd "$(dirname "$0")/.."
echo '[tests] Compiling Swift Testing targets'
swift build --build-tests --configuration release -Xswiftc -enable-testing

test_scratch="$(mktemp -d "${TMPDIR:-/private/tmp}/Neylu-test-monitor.XXXXXX")"
export NEYLU_TEST_PROGRESS="$test_scratch/progress.log"
export NSUnbufferedIO=YES
: > "$NEYLU_TEST_PROGRESS"
test_pid=''
monitor_pid=''
process_tree() {
  local parent="$1" child
  for child in $(pgrep -P "$parent" || true); do process_tree "$child"; done
  echo "$parent"
}
cleanup() {
  if [ -n "$monitor_pid" ]; then
    pkill -P "$monitor_pid" 2>/dev/null || true
    kill "$monitor_pid" 2>/dev/null || true
    wait "$monitor_pid" 2>/dev/null || true
  fi
  if [ -n "$test_pid" ] && kill -0 "$test_pid" 2>/dev/null; then
    for child in $(process_tree "$test_pid"); do kill "$child" 2>/dev/null || true; done
  fi
  rm -rf "$test_scratch"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo '[tests] Executing Swift Testing (runtime deadline: 180s)'
swift test --skip-build --configuration release --disable-xctest -Xswiftc -enable-testing "$@" &
test_pid=$!
(
  for ((elapsed=1; elapsed<=180; elapsed++)); do
    sleep 1
    kill -0 "$test_pid" 2>/dev/null || exit 0
    if ((elapsed % 30 == 0)); then
      echo "[tests] Runtime elapsed: ${elapsed}s; latest progress:"
      tail -n 3 "$NEYLU_TEST_PROGRESS"
    fi
    if ((elapsed == 90 || elapsed == 180)); then
      echo "[tests] Capturing test process stacks at ${elapsed}s"
      for child in $(process_tree "$test_pid"); do
        command_name="$(ps -p "$child" -o comm= 2>/dev/null || true)"
        echo "[tests] Process $child: $command_name"
        case "$command_name" in
          *NeyluPackageTests*|*swift-testing*|*xctest*|*swift-test)
            /usr/bin/sample "$child" 1 10 -file "$test_scratch/stack-$child.txt" 2>&1 || true
            if [ -f "$test_scratch/stack-$child.txt" ]; then cat "$test_scratch/stack-$child.txt"; fi
            ;;
        esac
      done
    fi
  done
  echo '::error::Swift Testing exceeded its 180s runtime deadline. Failing without skipping tests.'
  for child in $(process_tree "$test_pid"); do kill -TERM "$child" 2>/dev/null || true; done
  sleep 3
  for child in $(process_tree "$test_pid"); do kill -KILL "$child" 2>/dev/null || true; done
) &
monitor_pid=$!
set +e
wait "$test_pid"
test_status=$?
set -e
test_pid=''
exit "$test_status"
