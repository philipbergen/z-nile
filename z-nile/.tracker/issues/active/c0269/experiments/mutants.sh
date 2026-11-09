#!/usr/bin/env bash
# c0269 mutation check. It builds its OWN scratch repositories and takes no target (design review 003 F1: a guard that
# inspects a given directory accepted the real main checkout): a bare "origin" and a standalone clone of it, both in
# a fresh `mktemp -d` outside any checkout, which it removes at the end. Nothing here runs in or writes to the
# repository this file lives in except reads (a clone of its origin/main, and the issue's own files).
#   ./zn run --time 1200 -- bash z-nile/.tracker/issues/c0269/experiments/mutants.sh
# Each mutant must make the named check fail; the last ones prove the base cannot be forged.
set -u
ISSUE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
S=$ISSUE/acceptance
TOP=$(git -C "$ISSUE" rev-parse --show-toplevel) || exit 2
BASESHA=$(git -C "$TOP" rev-parse origin/main) || exit 2
dir=$(mktemp -d) || exit 2
case $dir in /*/tmp.*|/tmp/*) ;; *) echo "refusing: odd scratch dir $dir"; exit 2;; esac
git -C "$dir/.." rev-parse --show-toplevel >/dev/null 2>&1 && { echo "refusing: $dir is inside a checkout"; rm -rf "$dir"; exit 2; }
cleanup() { case $dir in /*/tmp.*|/tmp/*) rm -rf "$dir";; esac; }
trap cleanup EXIT
git clone -q --bare --no-hardlinks "$TOP" "$dir/origin.git" || exit 2
git -C "$dir/origin.git" update-ref refs/heads/main "$BASESHA" || exit 2   # the bare repository is our own
git clone -q --no-hardlinks "$dir/origin.git" "$dir/proto" || exit 2
cd "$dir/proto" || exit 2
git checkout -q --detach origin/main
python3 "$ISSUE/experiments/apply.py" "$PWD" || exit 2
mkdir -p z-nile/tests/acceptance/c0269
cp "$S/titles.spec.luau" "$S/narrow.py" z-nile/tests/acceptance/c0269/
git add -A && git -c user.email=t@example.invalid -c user.name=t commit -qm proto
D=z-nile/tests/acceptance/c0074/done-gate.spec.luau
spec() { (cd z-nile && lune run tests/run -- tests/acceptance/c0269/titles.spec.luau 2>&1 | grep -E '^FAIL|passed' | head -3); }
narrow() { python3 "$S/narrow.py" "$PWD" 2>&1 | head -2 | cut -c1-170; echo "narrow exit ${PIPESTATUS[0]}"; }
restore() { git checkout -q -- . ; git clean -fdq -e .cache; }
commit() { git add -A; git -c user.email=t@example.invalid -c user.name=t commit -qm "$1"; }
delassert() { python3 - <<'PY'
import pathlib
p=pathlib.Path("z-nile/tests/acceptance/c0074/done-gate.spec.luau"); t=p.read_text()
n='\t\tt.expect(gate.doneGate({})).toBe("affected")\n'
assert t.count(n)==1; p.write_text(t.replace(n,""))
PY
}
echo "baseline (the prototype itself): narrow must pass"; narrow
echo "M1 one title left (check.sh AC1 greps, narrow)"; sed -i '' 's/it("done runs the affected gate on the promoted/it("done runs the full gate on the promoted/' $D; grep -qF 'it("done runs the affected gate on the promoted, moved tree, then commits"' $D && echo "AC1 would PASS (bad)" || echo "AC1 red"; narrow; restore
echo "M2 a new spec repeats the old rule (spec AC2)"; mkdir -p z-nile/tests/unit; printf -- '-- so done skips the %s here\n' 'full gate' > z-nile/tests/unit/zz-stale.spec.luau; spec; restore
echo "M3 a scan that reads only titles (spec AC2 planted forms)"; sed -i '' 's/if has(flat, phrase) then/if has(flat, "it(\\"" .. phrase) then/' z-nile/tests/acceptance/c0269/titles.spec.luau; spec; restore
echo "M4 a deleted assertion (narrow)"; delassert; narrow; restore
echo "M5 a reworded comment (narrow)"; sed -i '' 's/-- fixture specs that drive done clone tests/-- fixture specs that drive done clone the tests/' $D; narrow; restore
echo "M6 a CRLF copy (narrow)"; python3 - <<'PY'
import pathlib
p=pathlib.Path("z-nile/tests/acceptance/c0074/done-gate.spec.luau"); p.write_bytes(p.read_bytes().replace(b"\n",b"\r\n"))
PY
narrow; restore
echo "M7 the spec's own inputs row missing (spec)"; sed -i '' '/c0269\/titles.spec.luau/d' z-nile/tests/inputs.tsv; spec; narrow; restore
echo "M8 another inputs row deleted (narrow)"; sed -i '' '1,/c0042/{/c0042/d;}' z-nile/tests/inputs.tsv; narrow; restore
echo "M9 a raftmate changes another line of done-gate.spec (narrow, says split the raft)"; echo '-- raftmate edit' >> $D; commit m9; narrow; git reset -q --hard HEAD~1
echo "M10 a deleted assertion committed, then the clone's origin/main moved to HEAD (narrow stays red)"; delassert; commit m10; git update-ref refs/remotes/origin/main HEAD; narrow; git reset -q --hard HEAD~1
echo "M11 a deleted assertion in a commit BELOW the substitutions, the local origin/main moved to that commit (narrow stays red)"; git reset -q --hard HEAD; git checkout -q --detach origin/main 2>/dev/null; git update-ref refs/remotes/origin/main "$BASESHA"
git checkout -q --detach "$BASESHA"; delassert; commit m11a; LOW=$(git rev-parse HEAD)
python3 "$ISSUE/experiments/apply.py" "$PWD"; mkdir -p z-nile/tests/acceptance/c0269; cp "$S/titles.spec.luau" "$S/narrow.py" z-nile/tests/acceptance/c0269/; commit m11b
git update-ref refs/remotes/origin/main "$LOW"; narrow; git update-ref refs/remotes/origin/main "$BASESHA"
echo "M12 the remote unreadable (narrow red, says so)"; git remote set-url origin /nonexistent/origin.git; narrow; git remote set-url origin "$dir/origin.git"
echo done
