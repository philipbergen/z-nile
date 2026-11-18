#!/usr/bin/env bash
# c0407 prep mutation check (E2). Run from a scratch worktree root (detached at origin/main) with prototype.patch applied
# to z-nile/tests/acceptance/c0084/commit-phase.spec.luau: ZN_C0407=<prep issue dir> bash E2-mutants.sh
# Engine mutants (M1, M2) and the spec runs go through the spec; text mutants (N*) run narrow.py on a mutated copy.
set -u
ROOT=$(pwd -P)
D=${ZN_C0407:?issue dir}
SPEC=z-nile/tests/acceptance/c0084/commit-phase.spec.luau
ENG=z-nile/engine/main.luau
W=$ROOT/.cache/c0407-mut
rm -rf "$W" && mkdir -p "$W"
cp "$SPEC" "$W/spec.orig"; cp "$ENG" "$W/main.orig"
restore() { cp "$W/spec.orig" "$SPEC"; cp "$W/main.orig" "$ENG"; }
trap restore EXIT
sub() { python3 - "$1" "$2" "$3" <<'PY'
import sys
p, a, b = sys.argv[1:]
s = open(p).read()
assert s.count(a) == 1, f"{a!r} occurs {s.count(a)} times in {p}"
open(p, "w").write(s.replace(a, b))
PY
}
runspec() { (cd z-nile && env -u ZN_PUBLISH_BROKER -u ZN_PUBLISH_TOKEN lune run tests/run -- tests/acceptance/c0084/commit-phase.spec.luau 2>&1) | grep -E '^FAIL|passed,|spec:[0-9]+:' | sed "s#$ROOT/##"; }
mut() { echo "== $1"; sub "$2" "$3" "$4" && runspec; restore; }
text() { echo "== $1"; cp "$W/spec.orig" "$W/m.luau"; sub "$W/m.luau" "$2" "$3" && { python3 "$D/acceptance/narrow.py" "$ROOT" "$W/m.luau"; echo "narrow rc=$?"; }; }

echo "== M0 prototype"; runspec
mut "M1 done appends the note with no space" "$ENG" 'subject ..= " " .. reading.note' 'subject ..= reading.note'
mut "M2 done prints the note but leaves the subject plain" "$ENG" 'subject ..= " " .. reading.note' 'subject ..= ""'
mut "M4 spec expects a space but not the note (any suffix)" "$SPEC" 'subject ..= " " .. note' 'subject ..= " claude"'
mut "M5 spec drops the plain-subject prefix check (expects only the note)" "$SPEC" 'local subject = `{raft}: bind {a}, {b}`' 'local subject = ""'
text "N1 deliver phase assertion removed" '		t.expect(ra[#ra].phase).toBe("deliver")
		local subject' '		local subject'
text "N2 subject assertion loosened to a prefix match" 't.expect(ra[#ra].subject).toBe(subject)' 't.expect(string.sub(ra[#ra].subject, 1, #subject)).toBe(subject)'
text "N3 summary phase assertion removed" '		t.expect(string.find(summary, "| deliver |", 1, true) ~= nil).toBe(true)
' ''
text "N4 override comment reworded" 'c0407 override: since' 'c0407 override: because'
text "N5 do return end added" '		local doneOut' '		do return end
		local doneOut'
