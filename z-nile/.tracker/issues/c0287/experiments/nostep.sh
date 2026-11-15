#!/usr/bin/env bash
# c0287: run spec files from z-nile's home of a checkout without a dispatched step's variables (the ZN_ variables a
# step carries unset, but ./zn run's ZN_BOUNDED_DEADLINE; z-nile/bin off PATH; the fence clears GitHub's), so a run inside `./zn dispatch` sees what an
# interactive run sees. d0355 (and d0298's runner change) own the leak; until one lands, trackerstate's broker cases are
# red in a dispatched step on main too (experiments/unfixed-dispatched-env.txt). The jail and the fence still guard
# the repository: only the step's variables go. Extra VAR=value words before `--` reach the specs (FAKE_DELAY=3).
#   ./zn run --time 3500 -- bash <this file> <checkout> <log> [VAR=value ...] -- <spec paths relative to z-nile/>
set -u
[[ $# -ge 3 ]] || { echo "usage: nostep.sh <checkout> <log> [VAR=value ...] -- <specs...>" >&2; exit 2; }
wt=$1
log=$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2") || exit 2
shift 2
envs=()
while [[ $# -gt 0 && $1 != -- ]]; do envs+=("$1"); shift; done
[[ ${1:-} == -- ]] || { echo "nostep.sh: missing -- before the spec paths" >&2; exit 2; }
shift
cd "$wt/z-nile" || exit 2
for v in $(compgen -e | grep '^ZN_' | grep -vx 'ZN_BOUNDED_DEADLINE'); do unset "$v"; done
PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/z-nile/bin$' | paste -sd: -)
export PATH
if env | grep '^ZN_' | grep -qv '^ZN_BOUNDED_DEADLINE='; then echo "nostep.sh: a ZN_ variable survived" >&2; exit 2; fi
{
  echo "start: $(date '+%Y-%m-%d %H:%M:%S %Z')  $(uptime | sed 's/.*load/load/')"
  if [[ ${#envs[@]} -gt 0 ]]; then echo "head: $(git rev-parse --short HEAD)  env: ${envs[*]}"; else echo "head: $(git rev-parse --short HEAD)  env: (none)"; fi
} > "$log"
start=$(date +%s)
if [[ ${#envs[@]} -gt 0 ]]; then env "${envs[@]}" lune run tests/run -- "$@" >> "$log" 2>&1; else lune run tests/run -- "$@" >> "$log" 2>&1; fi
code=$?
{
  echo "exit: $code  seconds: $(( $(date +%s) - start ))"
  echo "end: $(date '+%Y-%m-%d %H:%M:%S %Z')  $(uptime | sed 's/.*load/load/')"
} >> "$log"
exit $code
