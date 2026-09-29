#!/usr/bin/env bash
# Helpers for tracker check.sh files (acceptance criteria as executable checks).
#   source scripts/lib/ac.sh
#   check "AC1: description" <command> [args...]
#   finish
# Each check prints PASS/FAIL; finish exits non-zero if any failed.
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
export PATH="$HOME/.rokit/bin:$PATH"
_ac_failed=0
_ac_total=0

check() {
  local label="$1"; shift
  _ac_total=$((_ac_total + 1))
  local out
  if out=$("$@" 2>&1); then
    printf 'PASS  %s\n' "$label"
  else
    _ac_failed=$((_ac_failed + 1))
    printf 'FAIL  %s\n' "$label"
    printf '%s\n' "$out" | tail -n 25 | sed 's/^/      /'
  fi
}

finish() {
  if [[ $_ac_total -eq 0 ]]; then
    echo "FAIL  no acceptance checks defined (an empty check.sh never passes)"
    return 1
  fi
  printf -- '---- %d/%d criteria passed\n' "$((_ac_total - _ac_failed))" "$_ac_total"
  [[ $_ac_failed -eq 0 ]]
}
