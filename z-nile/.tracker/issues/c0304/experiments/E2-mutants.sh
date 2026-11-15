#!/usr/bin/env bash
# c0304 prep mutation check (E2). Run from the prep worktree's root with experiments/prototype.patch applied to
# z-nile/tests/acceptance/c0045/workstreams.spec.luau. Each mutant is applied in place, judged, and the file restored
# from a copy under .cache before the next; the engine and the spec are restored at the end whatever happens.
# Spec mutants (M*) run the spec with the dispatcher's publish env unset (E1); text mutants (N*) run narrow.py on a
# mutated copy. N7 and N15 build throwaway repositories under .cache: one whose base already holds the change, one
# whose base carries a c0178-style edit to the first case's clone setup (which no anchor touches: it must stay green).
# Revised after design review 001: F1 (narrow.py pins the whole file; N9 to N15 are lines only added), F3 (the
# spec runs include c0060/retrofit, which reads this file's text; M5 pushes through raw process.exec).
set -u
ROOT=$(pwd -P)
D=z-nile/.tracker/issues/c0304
SPEC=z-nile/tests/acceptance/c0045/workstreams.spec.luau
ENG=z-nile/engine/main.luau
LG=z-nile/engine/layergit.luau
W=$ROOT/.cache/c0304-mut
rm -rf "$W" && mkdir -p "$W"
cp "$SPEC" "$W/spec.orig"; cp "$ENG" "$W/main.orig"; cp "$LG" "$W/layergit.orig"
restore() { cp "$W/spec.orig" "$SPEC"; cp "$W/main.orig" "$ENG"; cp "$W/layergit.orig" "$LG"; }
trap restore EXIT
sub() { # file from to [count]: replace a literal that occurs exactly count (default 1) times
  python3 - "$1" "$2" "$3" "${4:-1}" <<'EOF'
import sys
p, a, b, n = sys.argv[1:]
s = open(p).read()
assert s.count(a) == int(n), f"{a!r} occurs {s.count(a)} times in {p}, expected {n}"
open(p, "w").write(s.replace(a, b))
EOF
}
runspec() {
  (cd z-nile && env -u ZN_PUBLISH_BROKER -u ZN_PUBLISH_TOKEN lune run tests/run -- tests/acceptance/c0045/workstreams.spec.luau tests/acceptance/c0060/retrofit.spec.luau 2>&1) |
    grep -E '^FAIL|passed,|^ +/.*\.spec:[0-9]+:' | sed "s#$ROOT/##"
}
spec_mutant() { # name file from to
  echo "== $1"; sub "$2" "$3" "$4" && runspec; restore
}
text_mutant() { # name from to [count]
  echo "== $1"; cp "$W/spec.orig" "$W/m.luau"; sub "$W/m.luau" "$2" "$3" "${4:-1}" &&
    { python3 "$D/acceptance/narrow.py" "$ROOT" "$W/m.luau"; echo "narrow rc=$?"; }
}

echo "== M0 the prototype itself"; runspec
spec_mutant "M1 worktree ignores --from" "$ENG" 'local base = from
		or if' 'local base = nil
		or if'
spec_mutant "M2 latestReview counts stream review files" "$LG" '"^final%-review%-(%d+)%.md$"' '"review%-.-(%d+)%.md$"'
spec_mutant "M3 the ref is cut at origin/main, not the raft work" "$SPEC" '{ "branch", "raft-tip", tip }' '{ "branch", "raft-tip", "origin/main" }'
spec_mutant "M4 the layer is not pushed (main's stale case)" "$SPEC" '		git(wt1, { "push", "-q", "origin", "HEAD" })
' ''
spec_mutant "M5 the push through raw process.exec" "$SPEC" '		git(wt1, { "push", "-q", "origin", "HEAD" })' '		process.exec("git", { "-C", wt1, "push", "-q", "origin", "HEAD" })'

echo "== N0 the prototype"; python3 "$D/acceptance/narrow.py" "$ROOT" "$W/spec.orig"; echo "narrow rc=$?"
text_mutant "N1 another case loses an assertion" '		t.expect(has(unknown.stderr, "no-such-ref")).toBe(true)
' ''
text_mutant "N2 case 1 loses the tip assertion" '		t.expect(git(stream, { "rev-parse", "HEAD" })).toBe(tip)
' ''
text_mutant "N3 case 2 loses the review assertion" '		t.expect(has(done.stderr, "no review-NNN.md")).toBe(true)
' ''
text_mutant "N4 a case is renamed" 'it("a single-issue raft is sequential"' 'it("a single issue raft is sequential"'
text_mutant "N5 the two --from lines name different refs" '"--from", "raft-tip" }), "again"' '"--from", "other" }), "again"'
text_mutant "N6 the preamble changes" 'local NO_GC: { [string]: string } = {}' 'local NO_GC: { [string]: string } = { x = "1" }'
text_mutant "N8 case 1 changes the rest of a --from line" '}), "worktree --from"))' '}), "worktree from"))'

text_mutant "N9 case 2's done call and assertions commented out" '		local done = tr(wt1, { "done", "R0010" })' '		--[[
		local done = tr(wt1, { "done", "R0010" })'
text_mutant "N10 case 1 returns before its branch and tip assertions" '		t.expect(git(stream, { "branch", "--show-current" })).toBe("ws-f0010")' '		do return end
		t.expect(git(stream, { "branch", "--show-current" })).toBe("ws-f0010")'
text_mutant "N11 case 2 rebinds done to a canned refusal" '		local done = tr(wt1, { "done", "R0010" })' '		local done = tr(wt1, { "done", "R0010" })
		done = { ok = false, code = 1, stdout = "", stderr = "no review-NNN.md" }'
text_mutant "N12 the push through raw process.exec" '		git(wt1, { "push", "-q", "origin", "HEAD" })' '		process.exec("git", { "-C", wt1, "push", "-q", "origin", "HEAD" })'
text_mutant "N13 an override comment reworded" "layer is pushed to the fixture's origin" "layer is pushed to origin"
echo "== N14 R0010-demo kept, with a branch of that name"; cp "$W/spec.orig" "$W/m.luau"
sub "$W/m.luau" '{ "branch", "raft-tip", tip }' '{ "branch", "R0010-demo", tip }' &&
  sub "$W/m.luau" '"--from", "raft-tip" }' '"--from", "R0010-demo" }' 2 &&
  { python3 "$D/acceptance/narrow.py" "$ROOT" "$W/m.luau"; echo "narrow rc=$?"; }

echo "== N7 a base that already holds the change"
R7=$W/n7; mkdir -p "$R7/z-nile/tests/acceptance/c0045"
git -C "$R7" init -q -b main
cp "$W/spec.orig" "$R7/$SPEC"
git -C "$R7" add -A && git -C "$R7" -c user.name=n7 -c user.email=n7@example.invalid commit -qm narrowed
# the bare origin is a clone of the committed fixture (the z-nile git wrapper refuses a push to any main)
git clone -q --bare "$R7" "$W/n7-origin.git" && git -C "$R7" remote add origin "$W/n7-origin.git" && git -C "$R7" fetch -q origin
python3 "$D/acceptance/narrow.py" "$R7"; echo "narrow rc=$?"

echo "== N15 a base with a c0178-style edit to the first case's clone setup, the prototype on top (must pass)"
R15=$W/n15; mkdir -p "$R15/z-nile/tests/acceptance/c0045"
git -C "$R15" init -q -b main
git show HEAD:"$SPEC" > "$R15/$SPEC"
sub "$R15/$SPEC" '		clone.isolated(root, seed)' '		clone.isolated(root, seed, { paths = { "z-nile", "pickman/.tracker" } })'
git -C "$R15" add -A && git -C "$R15" -c user.name=n15 -c user.email=n15@example.invalid commit -qm c0178-like
git clone -q --bare "$R15" "$W/n15-origin.git" && git -C "$R15" remote add origin "$W/n15-origin.git" && git -C "$R15" fetch -q origin
cp "$W/spec.orig" "$R15/$SPEC"
sub "$R15/$SPEC" '		clone.isolated(root, seed)' '		clone.isolated(root, seed, { paths = { "z-nile", "pickman/.tracker" } })'
python3 "$D/acceptance/narrow.py" "$R15"; echo "narrow rc=$?"
