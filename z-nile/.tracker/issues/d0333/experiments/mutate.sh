#!/usr/bin/env bash
SP=$1; W=$2
for m in M1 M2 M3 M4 M5 M6 M7 M8 M9; do
  echo "== $m"
  MUTANT=$m bash "$(dirname "$0")/proto-run.sh" "$SP" "$W" 2>&1 | grep -E '^FAIL .* :: |passed, .* failed, 3 spec|expected|failed \(' | cut -c1-330
done
