#!/usr/bin/env bash
# c0411 prep mutation check for AC1 (acceptance/narrow.py), experiment E4. Run bounded, from the scratch worktree's root:
#   ./zn run --time 120 -- bash <this file> <the prep worktree's c0411 folder>   (experiments/prototype.patch applied in that worktree). It reads the spec and writes only copies under the scratch tree's .cache/c0411-narrow.
# Each mutant is a copy of the edited spec with one change, judged by narrow.py's second argument; rc=1 is a kill.
set -u
ROOT=$(pwd -P); D=$1
SPEC=z-nile/tests/acceptance/c0043/rounds.spec.luau
W=$ROOT/.cache/c0411-narrow; rm -rf "$W"; mkdir -p "$W"; cp "$SPEC" "$W/spec.orig"
mut() { # name from to
  cp "$W/spec.orig" "$W/m.luau"
  python3 - "$W/m.luau" "$2" "$3" <<'PY'
import sys
p, a, b = sys.argv[1:]
s = open(p).read()
assert s.count(a) == 1, f"{a!r} occurs {s.count(a)} times"
open(p, "w").write(s.replace(a, b))
PY
  echo "== $1"; python3 "$D/acceptance/narrow.py" "$ROOT" "$W/m.luau" | head -3; echo "narrow rc=${PIPESTATUS[0]}"
}
echo "== N0 the prototype"; python3 "$D/acceptance/narrow.py" "$ROOT" "$W/spec.orig"; echo "narrow rc=$?"
mut "N1 the retired folder left out" ', "rafts/retired" }' ' }'
mut "N2 a hand-written root list" 'projects.roots(projects.load(TOP))' '{ "pickman/.tracker", "z-nile/.tracker" }'
mut "N3 the final assertion dropped" '		t.expect(ids).toEqual(want)
' ''
mut "N4 --[[ around the assertion" '		t.expect(ids).toEqual(want)
' '		--[[ t.expect(ids).toEqual(want) ]]
'
mut "N5 do return end after want" '		table.sort(want)
' '		table.sort(want)
		do return end
'
mut "N6 want rebound to ids" '		t.expect(ids).toEqual(want)' '		want = ids
		t.expect(ids).toEqual(want)'
mut "N7 another case loses an assertion" '		t.expect(by[r70][4]).toBe("second-order") -- its first design review used the new format
' ''
mut "N8 sort dropped from want" '		table.sort(want)
' ''
mut "N9 override comment reworded" '-- c0411 override: rafts live' '-- c0411 override: rafts sit'
mut "N10 allRoots instead of roots" 'projects.roots(projects.load(TOP))' 'projects.allRoots(projects.load(TOP))'
