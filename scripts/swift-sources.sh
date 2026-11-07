# shellcheck shell=bash
# Shared native source inventory; executable entry points are added by callers.
# Sources/Updater/main.swift is intentionally a separate helper target.
neylu_sources=()
for neylu_source in Sources/*.swift; do
  if [[ "$neylu_source" != Sources/main.swift ]]; then
    neylu_sources+=("$neylu_source")
  fi
done
