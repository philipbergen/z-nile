#!/usr/bin/env bash
# Helpers for tracker check.sh files (acceptance criteria as executable checks).
#   source z-nile/lib/ac.sh
#   check "AC1: description" <command> [args...]
#   finish
# Each check prints PASS/FAIL; finish exits non-zero if any failed.
# With AC_LIST set (non-empty), check only prints LIST <label> and runs nothing; finish says "listed".
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
# Guard git for everything this check.sh runs (testing skill, "Specs never touch the real repository"). The guards
# missing fails closed (c0114): a check.sh never runs unfenced.
if [[ ! -f z-nile/lib/fence.sh ]]; then
  echo "ac.sh: $(pwd -P)/z-nile/lib/fence.sh is missing: refusing to run checks without the repository guards" >&2
  exit 1
fi
source z-nile/lib/fence.sh || exit 1
pickman_fence "$(pwd -P)" || exit 1
export PATH="$HOME/.rokit/bin:$PATH"
_ac_failed=0
_ac_total=0

check() {
  local label="$1"; shift
  _ac_total=$((_ac_total + 1))
  if [[ -n ${AC_LIST:-} ]]; then
    printf 'LIST  %s\n' "$label"
    return 0
  fi
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
  if [[ -n ${AC_LIST:-} ]]; then
    printf -- '---- %d criteria listed (none run)\n' "$_ac_total"
    return 0
  fi
  printf -- '---- %d/%d criteria passed\n' "$((_ac_total - _ac_failed))" "$_ac_total"
  [[ $_ac_failed -eq 0 ]]
}
