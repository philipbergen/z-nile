#!/usr/bin/env bash
# c0288 prep: run c0260's three model-calling specs (loop, record, provenance) on a c0260 prototype's z-nile/, without a
# dispatched step's variables (d0298's STEP_VARS unset, z-nile/bin off PATH, as d0297's experiments/nostep.sh does), so
# the fixtures' `./zn` never reaches the dispatcher's broker. The jail and the fence still guard the repository.
#   bash nostep-run.sh <prototype>/z-nile <log> [spec ...]   (default: the three specs, from the prototype's own c0260 folder)
set -euo pipefail
home=$1 log=$2; shift 2
specs=("$@")
[[ ${#specs[@]} -gt 0 ]] || specs=(.tracker/issues/c0260/acceptance/loop.spec.luau .tracker/issues/c0260/acceptance/record.spec.luau .tracker/issues/c0260/acceptance/provenance.spec.luau)
TOP="$(git -C "$home" rev-parse --show-toplevel)"
cleanpath=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/z-nile/bin$' | paste -sd: -)
{ echo "load: $(uptime)"; date; } > "$log"
cd "$home" && env -u ZN_DISPATCH -u ZN_HEADLESS -u ZN_DISPATCH_DIR -u ZN_DISPATCH_HOME -u ZN_REAL_GIT -u ZN_REAL_GH \
  -u ZN_PUBLISH_BROKER -u ZN_PUBLISH_TOKEN -u ZN_DISPATCHER_PID -u ZN_AGENT_GH_TOKEN -u ZN_MEASURE_FILE PATH="$cleanpath" \
  "$TOP/zn" run --time 1700 -- lune run tests/run -- "${specs[@]}" >> "$log" 2>&1 || true
{ date; echo "load: $(uptime)"; } >> "$log"
grep -E "^(PASS|FAIL) |spec files$|^slowest" "$log" | grep -v "^PASS .* :: " || true
