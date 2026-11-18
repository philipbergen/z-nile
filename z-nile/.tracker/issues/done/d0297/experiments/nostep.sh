#!/usr/bin/env bash
# d0297: run the slow-tier specs of the Affected list from z-nile's home without a dispatched step's variables
# (d0298's STEP_VARS unset, z-nile/bin off PATH), so they run where z-run runs (design review 001 F2). The jail and
# the fence still guard the repository: only the step's variables go, as d0298's runner change does for every spec.
# Takes no arguments; prints one PASS/FAIL line per file and the summary. Bounded by ./zn run.
#   bash z-nile/.tracker/issues/<active/>d0297/experiments/nostep.sh
set -euo pipefail
[[ $# -eq 0 ]] || { echo "nostep.sh takes no arguments" >&2; exit 2; }
TOP="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
cd "$TOP"
touched=(z-nile/lib/select.luau z-nile/affected.luau z-nile/engine/main.luau z-nile/skills/zz-test/SKILL.md)
picked=$("$TOP/zn" run --time 120 -- lune run z-nile/affected -- --project z-nile "${touched[@]}")
slow=()
while IFS= read -r spec; do
  [[ -n $spec ]] || continue
  if grep -qF -e "$spec" z-nile/tests/slow.tsv; then slow+=("$spec"); fi
done <<< "$picked"
echo "${#slow[@]} slow-tier specs"
cleanpath=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/z-nile/bin$' | paste -sd: -)
out=$(cd z-nile && env -u ZN_DISPATCH -u ZN_HEADLESS -u ZN_DISPATCH_DIR -u ZN_DISPATCH_HOME -u ZN_REAL_GIT -u ZN_REAL_GH \
  -u ZN_PUBLISH_BROKER -u ZN_PUBLISH_TOKEN -u ZN_DISPATCHER_PID -u ZN_AGENT_GH_TOKEN PATH="$cleanpath" \
  "$TOP/zn" run --time 3500 -- lune run tests/run -- "${slow[@]}" 2>&1) || true
grep -E "^(PASS|FAIL) [^ ]+\.spec\.luau:|spec files$" <<< "$out" | sort
