#!/usr/bin/env bash
# d0297 prep: the mutation check and the correct variants. Takes no directory: it clones the repository this file
# sits in into a fresh mktemp -d folder (no hardlinks, origin removed), applies prototype.patch, copies d0297's
# acceptance specs and proof, then for each row applies one edit, runs that row's specs, and puts the file back as
# the prototype had it.
# A mutant must fail on an assertion ("expected ..."); a correct variant must pass. Moves no ref of any repository
# but its own clone, and removes the clone when it ends. Run it bounded:
#   ./zn run --time 1800 -- bash z-nile/.tracker/issues/d0297/experiments/mutants.sh
set -euo pipefail
[[ $# -eq 0 ]] || { echo "mutants.sh takes no arguments" >&2; exit 2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TOP="$(git -C "$HERE" rev-parse --show-toplevel)"
ITEM="$(dirname "$HERE")"
scratch="$(mktemp -d)"
case "$scratch" in
  /tmp/* | /private/tmp/* | /var/folders/* | /private/var/folders/*) ;;
  *) echo "refusing an odd scratch path: $scratch" >&2; exit 2 ;;
esac
if git -C "$scratch" rev-parse --git-dir > /dev/null 2>&1; then
  echo "refusing: $scratch lies inside a checkout" >&2
  exit 2
fi
trap 'rm -rf -- "$scratch"' EXIT
clone="$scratch/proto"
git clone -q --no-hardlinks "$TOP" "$clone"
git -C "$clone" remote remove origin
git -C "$clone" apply "$HERE/prototype.patch"
rel="${ITEM#"$TOP"/}"
mkdir -p "$clone/$rel"
cp -R "$ITEM/acceptance" "$ITEM/proofs" "$clone/$rel/"
A=".tracker/issues/d0297/acceptance"
if [[ $rel == z-nile/.tracker/issues/active/d0297 ]]; then A=".tracker/issues/active/d0297/acceptance"; fi
PF="${A%/acceptance}/proofs"

# edit <file> <old> <new>: replace exactly one occurrence, or stop
edit() {
  python3 -I - "$clone/$1" "$2" "$3" << 'EOF'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
if text.count(old) != 1:
    sys.exit(f"{path}: expected one occurrence of {old!r}, found {text.count(old)}")
open(path, "w").write(text.replace(old, new))
EOF
}

run() { (cd "$clone/z-nile" && lune run tests/run -- "$@" 2>&1) || true; }

# check.sh's AC4 command (its bash -c body, read from the item's check.sh), run against the clone; prints
# "FAIL :: AC4 expected ..." when it fails, so a row can name AC4 in place of a spec
ac4() {
  local body
  body=$(python3 -I - "$ITEM/check.sh" << 'EOF2'
import sys
text = open(sys.argv[1]).read()
start = text.index("bash -c '", text.index('check "AC4:')) + len("bash -c '")
print(text[start:text.index("\n'\n", start)])
EOF2
)
  if ZN_ROOT="$clone" bash -c "$body" 2>&1; then echo "AC4 passed"; else echo "FAIL :: AC4 (expected its text)"; fi
}

bad=0
row() { # row <kind mutant|variant> <id> <file> <old> <new> <spec>...
  local kind=$1 id=$2 file=$3 old=$4 new=$5
  shift 5
  cp "$clone/$file" "$scratch/saved"
  edit "$file" "$old" "$new"
  local out
  if [[ $1 == AC4 ]]; then out=$(ac4); else out=$(run "$@"); fi
  cp "$scratch/saved" "$clone/$file"
  if [[ $kind == mutant ]]; then
    if grep -q "^FAIL .*::" <<< "$out" && grep -q "expected" <<< "$out"; then
      echo "KILLED  $id: $(grep -m1 '^FAIL .*::' <<< "$out")"
    else
      echo "SURVIVED $id"; bad=1
      grep -E "^FAIL|error|passed" <<< "$out" | head -5
    fi
  else
    if grep -q "^FAIL" <<< "$out"; then
      echo "RED     $id (a correct variant fails)"; bad=1
      grep -E "^FAIL" <<< "$out" | head -5
    else
      echo "GREEN   $id"
    fi
  fi
}

SEL=z-nile/lib/select.luau
AFF=z-nile/affected.luau
MAIN=z-nile/engine/main.luau
GATE=z-nile/check.sh
FILTER="if projects.rootOf(spec, ctx.rules.roots) == nil then"
CALL='"--project", project.name, "--own-acceptance" }'

echo "== the prototype itself"
out=$(run "$A/select.spec.luau" "$A/cli.spec.luau" "$PF/finish.spec.luau" tests/tooling/own-acceptance-callers.spec.luau \
  tests/tooling/select-scope.spec.luau tests/tooling/watch.spec.luau tests/acceptance/c0165/select.spec.luau)
grep -E "spec files$" <<< "$out"
grep -q "^FAIL" <<< "$out" && { echo "the prototype is red"; grep "^FAIL" <<< "$out"; exit 1; }
out=$(ac4)
echo "$out"
grep -q "^FAIL" <<< "$out" && exit 1
# F4: a change to a file a gate or forwarder runs from selects the tooling scan
for f in z-nile/check.sh scripts/affected.luau z-nile/specs.luau zn; do
  picked=$(cd "$clone" && lune run z-nile/affected -- "$f")
  if grep -qxF z-nile/tests/tooling/own-acceptance-callers.spec.luau <<< "$picked"; then
    echo "selected by $f: own-acceptance-callers"
  else
    echo "NOT selected by $f"; exit 1
  fi
done

echo "== mutants"
row mutant M1-no-filter $SEL "$FILTER" "if true then" "$A/select.spec.luau"
row mutant M2-current-exempt $SEL "$FILTER" \
  "if projects.rootOf(spec, ctx.rules.roots) == nil or table.find(ctx.current or {}, spec) then" "$A/select.spec.luau"
row mutant M3-acceptance-substring $SEL "$FILTER" 'if not string.find(spec, "/acceptance/", 1, true) then' \
  "$A/select.spec.luau"
row mutant M4-issues-substring $SEL "$FILTER" 'if not string.find(spec, "/issues/", 1, true) then' "$A/select.spec.luau"
row mutant M5-own-ignored $SEL "for _, spec in own do" "for _ = 1, 0 do local spec = own[1]" \
  "$A/select.spec.luau"
row mutant M6-own-skips-project-filter $SEL "	local out: { string } = {}
	for _, spec in picked do" "	local out: { string } = table.clone(ctx.own or {})
	for _, spec in picked do" "$A/select.spec.luau"
row mutant M7-own-disables-filter $SEL "$FILTER" \
  "if projects.rootOf(spec, ctx.rules.roots) == nil or ctx.own ~= nil then" "$A/select.spec.luau" "$A/cli.spec.luau"
row mutant M8-flag-not-parsed $AFF 'elseif a == "--own-acceptance" then' 'elseif a == "--own-acceptance-x" then' \
  "$A/cli.spec.luau"
row mutant M9-flag-always-on $AFF "if ownAcceptance then" "if true then" "$A/cli.spec.luau"
row mutant M10-finish-omits-flag $MAIN "$CALL" '"--project", project.name }' "$A/cli.spec.luau" "$PF/finish.spec.luau"
row mutant M11-gate-passes-flag $GATE 'lune run z-nile/affected -- --project "$n"' \
  'lune run z-nile/affected -- --project "$n" --own-acceptance' "$A/cli.spec.luau"
row mutant M11b-gate-passes-flag-tooling $GATE 'lune run z-nile/affected -- --project "$n"' \
  'lune run z-nile/affected -- --project "$n" --own-acceptance' tests/tooling/own-acceptance-callers.spec.luau

row mutant M12-usage-line-deleted $AFF "--   ... --own-acceptance                         -- also the layer's own sequestered acceptance specs (./zn finish
--                                                -- only: it records them in results.txt; the gate never passes it)
" "" AC4
row mutant M13-scope-keeps-own $SEL "	plain.own = nil
" "" "$A/select.spec.luau"
row mutant M14-own-whenever-project $AFF "if ownAcceptance then" "if ownAcceptance or only ~= nil then" "$A/cli.spec.luau"
row mutant M15-flag-in-dispatcher z-nile/engine/dispatcher.luau "local dispatcher = {}" 'local dispatcher = {}
dispatcher.OWN = "--own-acceptance"' "$A/cli.spec.luau"
row mutant M16-flag-in-a-call-without-results z-nile/engine/dispatcher.luau "local dispatcher = {}" 'local dispatcher = {}
dispatcher.SELECT = { "run", "z-nile/affected", "--", "--own-acceptance" }' "$A/cli.spec.luau"

echo "== correct variants"
row variant V1-tracker-substring $SEL "$FILTER" 'if not string.find(spec, "/.tracker/", 1, true) then' \
  "$A/select.spec.luau" "$A/cli.spec.luau"
row variant V2-flag-appended $MAIN "$CALL" '"--project", project.name }
			table.insert(argv, "--own-acceptance")' "$A/cli.spec.luau"
row variant V3-flag-first $MAIN "$CALL" '"--own-acceptance", "--project", project.name }' "$A/cli.spec.luau"
row variant V4-gate-comment-names-flag $GATE 'lune run z-nile/affected -- --project "$n"' \
  'lune run z-nile/affected -- --project "$n" # never --own-acceptance (finish only)
    true' "$A/cli.spec.luau"
row variant V5-usage-reworded $AFF "-- also the layer's own sequestered acceptance specs (./zn finish" \
  "-- adds the current layer's own sequestered specs (for ./zn finish" AC4

# V6: finish moved out of main.luau into its own engine module (c0180's split): the wiring case must stay green
echo "-- V6 setup" > /dev/null
python3 -I - "$clone/$MAIN" "$clone/z-nile/engine/finishcmd.luau" << 'EOF2'
import sys
main, dest = sys.argv[1], sys.argv[2]
text = open(main).read()
start = text.index("\nfunction cmd.finish(")
stop = text.index("\nfunction ", start + 1)
open(dest, "w").write("--!strict\n-- c0180-style split of cmd.finish (V6)\nlocal cmd = {}" + text[start:stop] + "\nreturn cmd\n")
open(main, "w").write(text[:start] + "\n-- cmd.finish lives in finishcmd.luau (V6)\n" + text[stop:])
EOF2
git -C "$clone" add -N z-nile/engine/finishcmd.luau
out=$(run "$A/cli.spec.luau")
if grep -q "^FAIL" <<< "$out"; then echo "RED     V6-finish-in-its-own-module"; bad=1; grep "^FAIL" <<< "$out" | head -5; else echo "GREEN   V6-finish-in-its-own-module"; fi
exit $bad
