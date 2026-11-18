#!/usr/bin/env bash
# c0374 prep mutation check. Run from a scratch worktree of origin/main with experiments/prototype.patch applied to
# z-nile/tests/acceptance/c0120/finished.spec.luau and the acceptance files copied to z-nile/tests/acceptance/c0374/.
# Each mutant is applied in place, judged by the acceptance spec (M*) or narrow.py (N*), and the file restored.
# Usage: bash mutants.sh <narrow.py>   (run with ./zn run --time 1800)
set -u
ROOT=$(pwd -P)
SPEC=z-nile/tests/acceptance/c0120/finished.spec.luau
NARROW=$1
W=$ROOT/.cache/c0374-mut
rm -rf "$W" && mkdir -p "$W"
cp "$SPEC" "$W/spec.orig"
restore() { cp "$W/spec.orig" "$SPEC"; }
trap restore EXIT
sub() { python3 - "$1" "$2" "$3" "${4:-1}" <<'EOF'
import sys
p, a, b, n = sys.argv[1:]
s = open(p).read()
assert s.count(a) == int(n), f"{a!r} occurs {s.count(a)} times in {p}, expected {n}"
open(p, "w").write(s.replace(a, b))
EOF
}
runacc() { (cd z-nile && lune run tests/run -- tests/acceptance/c0374/reads-homes.luau 2>&1) | grep -E '^FAIL|passed,|expected' | sed "s#$ROOT/##" | cut -c1-230; }
spec_mutant() { echo "== $1"; sub "$SPEC" "$2" "$3" "${4:-1}" && runacc; restore; }
text_mutant() { echo "== $1"; cp "$W/spec.orig" "$W/m.luau"; sub "$W/m.luau" "$2" "$3" "${4:-1}" && { python3 "$NARROW" "$ROOT" "$W/m.luau" | head -3; }; }

echo "== M0 the prototype"; runacc
spec_mutant "M1 every bare name is a message, quoted or not" 'local message = single ~= nil
										and not string.find(l.path, "/", 1, true)
										and (single[l.line] or {})[l.first] == true' 'local message = not string.find(l.path, "/", 1, true)'
spec_mutant "M2 every literal inside single quotes is a message" 'and not string.find(l.path, "/", 1, true)
										and (single[l.line] or {})[l.first] == true' 'and (single[l.line] or {})[l.first] == true'
spec_mutant "M3 a line with a single quote is a message wholly" '(single[l.line] or {})[l.first] == true' 'single[l.line] ~= nil'
spec_mutant "M4 no stack: a quote toggles, no escape and no comment" 'elseif c == "\\" then
				skip = true' 'elseif false then
				skip = true'
spec_mutant "M5 an unbalanced text is not reported" 'if not single then' 'if false then'
spec_mutant "M6 the mask resets at each line (a quote cannot span lines)" 'line += 1
			col = 0' 'line += 1
			col = 0
			stack = { "normal" }'
spec_mutant "M7 a path missing before the move is reported" 'and world.before(l.dir .. l.path)' 'and true'
spec_mutant "M8 a comment is not skipped" 'elseif not comment then' 'elseif true then'

spec_mutant "M9 a \$( never pushes a context" 'elseif c == "(" and prev == "$" then' 'elseif false then'
spec_mutant "M10 a # inside a word starts a comment" 'and string.find(prev, "^[%s;|&(]$") then' 'then'

echo "== N0 the prototype"; python3 "$NARROW" "$ROOT" "$W/spec.orig" | head -2
text_mutant "N1 another case loses an assertion" '		t.expect(rewrites.relative("pickman", "pickman/.tracker/x")).toBe(".tracker/x")
' ''
text_mutant "N2 the last case is commented out in part" '			t.expect(read > 0).toBe(true)' '			--[[ t.expect(read > 0).toBe(true) ]]'
text_mutant "N3 the helper comment is reworded" '-- c0374: the bytes of `text` inside single quotes' '-- c0374: the chars of `text` inside single quotes'
text_mutant "N4 do return end added to the last case" '			local pre, why = rewrites.premove(TOP)' '			do return end
			local pre, why = rewrites.premove(TOP)'
text_mutant "N5 a second hunk: the loop also skips files named alone outside quotes" 'and not string.find(l.path, "/", 1, true)' 'and not string.find(l.path, "/", 1, true) or l.word == "zn"'
