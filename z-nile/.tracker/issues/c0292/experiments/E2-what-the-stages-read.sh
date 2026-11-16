#!/usr/bin/env bash
# E2 (c0292 prep): which files of an issue folder the gate's format and lint stages read, and whether a warning alone
# fails the lint stage. Writes only under its own mktemp -d, removed on exit. Run from the repository root:
#   ./zn run --time 60 -- bash z-nile/.tracker/issues/c0292/experiments/E2-what-the-stages-read.sh
set -uo pipefail
export PATH="$HOME/.rokit/bin:$PATH"
root=$(pwd -P)
tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
cp "$root/stylua.toml" "$root/selene.toml" "$tmp/"
d="$tmp/z-nile/.tracker/issues/c9999" && mkdir -p "$d/acceptance" "$d/experiments"
bad='local  x = require("@z-nile/nothing")
local s = "\{"   ;return  {}'
printf '%s\n' "$bad" > "$d/check.sh"                     # a check.sh holding broken Luau text
printf '%s\n' "$bad" > "$d/experiments/ref-spec.luau.txt" # a reference text
printf '%s\n' "$bad" > "$d/experiments/notes.md"
run() { (cd "$tmp" && stylua --check z-nile/.tracker/issues/c9999 >/dev/null 2>&1); f=$?; (cd "$tmp" && selene --quiet z-nile/.tracker/issues/c9999 >/dev/null 2>&1); l=$?; echo "$f $l"; }
a=$(run); echo "a) only .sh, .luau.txt and .md hold the bad text: stylua $a (exit codes: stylua selene)"
printf 'local a = 1\nlocal function f()\n\tlocal a = 2\n\treturn a\nend\nreturn { a, f }\n' > "$d/acceptance/warn.spec.luau"
b=$(run); echo "b) plus a formatted .luau whose only problem is a selene warning (shadowing = \"warn\"): $b"
printf '%s\n' "$bad" > "$d/experiments/E9.luau"
c=$(run); echo "c) plus the bad text as experiments/E9.luau: $c"
[[ $a == "0 0" && $b == "0 1" && $c == "1 1" ]] && echo "E2 PASS" || { echo "E2 FAIL"; exit 1; }
