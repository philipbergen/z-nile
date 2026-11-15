#!/usr/bin/env bash
# c0288 prep mutation check of acceptance/pins.sh (both modes). Builds a scratch git repository under $TMPDIR (never the
# real one) holding c0260's specs as the base commit, then for the base, the intended change and each mutant writes the
# working copy and runs `pins.sh limits 120 <dir>` and `pins.sh shape 120 <dir> <base>`, printing pass/FAIL.
#   bash pins-mutants.sh <c0260's acceptance folder> <c0288's pins.sh>
set -euo pipefail
A=$(cd "$1" && pwd -P) P=$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")
PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/z-nile/bin$' | paste -sd: -) # plain git: the scratch repo is ours
S=$(mktemp -d) R=$S/repo
git init -q "$R" && mkdir -p "$R/specs" && cp "$A"/*.spec.luau "$R/specs/"
git -C "$R" add -A && git -C "$R" -c user.name=c0288 -c user.email=c0288@example.invalid commit -qm base
base=$(git -C "$R" rev-parse HEAD)
reset() { git -C "$R" checkout -q -- . && git -C "$R" clean -qfd; }
fix() { for f in loop record provenance; do sed -i '' 's/^stall_seconds = 30$/stall_seconds = 120/' "$R/specs/$f.spec.luau"; done; }
run() {
  local out=""
  for m in limits shape; do
    if (cd "$R" && bash "$P" $m 120 specs "$base" >/dev/null 2>&1); then out+="$m=pass "; else out+="$m=FAIL "; fi
  done
  printf '%-6s %s(%s)\n' "$1" "$out" "$2"; reset
}
s() { sed -i '' "$1" "$R/specs/$2"; }
run base "unchanged: every limit 30 s"
fix; run fixed "the intended change: the four lines at 120"
fix; awk 'BEGIN{n=0} /^stall_seconds = 120$/{n++; if(n==2){print "stall_seconds = 30"; next}} {print}' "$R/specs/loop.spec.luau" > "$S/x" && mv "$S/x" "$R/specs/loop.spec.luau"; run M1 "loop's WITH_FALLBACKS limit left at 30"
fix; s 's/^stall_seconds = 120$/stall_seconds = 60/' record.spec.luau; run M2 "record's limit 60, still short"
fix; grep -v 'idea-call-1/beat`)).toBe(true)' "$R/specs/loop.spec.luau" > "$S/x" && mv "$S/x" "$R/specs/loop.spec.luau"; run M3 "the beat assertion deleted"
fix; s 's/^stall_seconds = 120$/stall_seconds = 120\ntool_seconds = 60/' provenance.spec.luau; run M4 "a short tool limit added"
fix; s 's/^return t.spec(/local X = "[dispatch]\\nstall_seconds = 10\\n"\nreturn t.spec(/' record.spec.luau; run M5 "a short limit inside a Luau string"
fix; s 's/^stall_seconds = 120$/stall_seconds = 30 # tests a stall/' provenance.spec.luau; run M6 "the branch marks a short limit as a stall test"
fix; cp "$R/specs/cut.spec.luau" "$R/specs/extra.spec.luau"; run M7 "a spec added"
fix; rm "$R/specs/cut.spec.luau"; run M8 "a spec deleted"
fix; s 's/^stall_seconds = 120$/stall_seconds   =   120/' record.spec.luau; run ok1 "spacing only: still a plain limit line"
fix; grep -v '^stall_seconds = 120$' "$R/specs/provenance.spec.luau" > "$S/x" && mv "$S/x" "$R/specs/provenance.spec.luau"; run ok2 "provenance's line dropped: the default, 300 s"
s 's/^stall_seconds = 30$/stall_seconds = 10 # tests a stall/' provenance.spec.luau; (cd "$R" && git add -A && git -c user.name=c0288 -c user.email=c0288@example.invalid commit -qm marked); base=$(git -C "$R" rev-parse HEAD); fix; run ok3 "c0260's own design marks a stall test (in the base); the branch leaves it"
rm -rf "$S"
