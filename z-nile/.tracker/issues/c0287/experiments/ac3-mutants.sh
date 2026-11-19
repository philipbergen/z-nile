#!/usr/bin/env bash
# c0287 (design review 001 F3): AC3's command on a clone of the prototype commit under a fresh `mktemp -d` (removed on
# any exit), unmutated and with one wrong edit each to the fake's or a spec's unchanged parts; every edit must fail it.
# The clone's origin/main is the prototype's base (efa610174). Bounded by ./zn run:
#   ./zn run --time 120 -- bash <this file>
set -u
PROTO=0e79784e3 BASE=efa610174
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
A="$(dirname "$here")/acceptance"
src=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir) || exit 2
t=$(mktemp -d "${TMPDIR:-/tmp}/c0287-ac3.XXXXXX") || exit 2
t=$(cd "$t" && pwd -P)
case $t in */c0287-ac3.*) ;; *) exit 2 ;; esac
trap 'rm -rf "$t"' EXIT
trap 'exit 143' TERM INT HUP
git clone -q --shared --no-checkout "$src" "$t/r" && git -C "$t/r" checkout -q "$PROTO" || exit 2
git -C "$t/r" update-ref refs/remotes/origin/main "$BASE" || exit 2
cd "$t/r/z-nile" || exit 2
ac3() { bash -c 'b=$(git merge-base HEAD origin/main) || exit 1; for f in acceptance/c0117/control-cli.spec acceptance/c0117/trackerstate.spec lib/fakecli; do diff <(git diff "$b" -- "tests/$f.luau" | grep -v "^index \|^@@") "$1/${f##*/}.luau.expected.diff" > /dev/null || exit 1; done' _ "$A"; }
sub() { python3 -I -c 'import sys; p,o,n=sys.argv[1:4]; s=open(p).read(); assert s.count(o)==1, o; open(p,"w").write(s.replace(o,n))' "$@"; }
try() { if ac3; then echo "SURVIVED $1"; else echo "killed $1"; fi; git checkout -q -- .; }
if ac3; then echo "control: AC3 passes on the prototype"; else echo "CONTROL FAILED"; fi
F=tests/lib/fakecli.luau S=tests/acceptance/c0117/control-cli.spec.luau
sub $F 'Bash"}]}}'"'"'; sleep 18;' 'Bash"}]}}'"'"'; sleep 8;'; try "silenttool cut to 8 s"
sub $F 'for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do' 'for i in 1 2 3 4 5 6 7 8; do'; try "slowreview cut to 8 beats"
sub $F '"quietreview) sleep 20; "' '"quietreview) sleep 9; "'; try "quietreview cut to 9 s"
sub $S 'if os.time() - started >= seconds then
			return false' 'if os.time() - started >= seconds then
			return true'; try "within true at its bound"
sub $S 'free(`{dirOf("c0050")}/run.lock`)' 'free(`{dirOf("c0050")}/run.lck`)'; try "a misspelt lock path"
sub $S 'return not r.ok and string.find(r.stderr, "No such process", 1, true) ~= nil' 'return not r.ok'; try "dead on any kill failure"
