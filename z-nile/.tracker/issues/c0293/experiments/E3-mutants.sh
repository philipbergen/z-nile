#!/usr/bin/env bash
# c0293 mutation check. Self-contained: it takes no directory and touches no checkout it was not given. It makes a
# fresh scratch clone of this repository, checks out BASE, applies prototype.patch, copies this issue's folder in,
# commits there with a one-off identity, then applies each mutant in the clone and runs the row's spec, which must fail
# on an assertion (not a syntax or require error). Run it from any checkout, bounded:
#   ./zn run --time 900 -- bash z-nile/.tracker/issues/c0293/experiments/E3-mutants.sh
# (once c0194 lands, `./zn tmp new` replaces the mktemp below).
set -euo pipefail
BASE=7861c8506
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ISSUE="$(cd "$HERE/.." && pwd -P)"
SRC="$(git -C "$HERE" rev-parse --show-toplevel)"
W="$(mktemp -d "${TMPDIR:-/tmp}/c0293-mutants.XXXXXX")"
W="$(cd "$W" && pwd -P)" # physical: tests/run strips the physical cwd from a spec path
cleanup() { # remove the scratch folder only when it is the one made above
  case "$W" in */c0293-mutants.??????) [[ -d $W/.git || -d $W/r/.git ]] && rm -rf -- "$W" ;; esac
}
trap cleanup EXIT
P="$W/r"
git clone -q "$SRC" "$P"
git -C "$P" checkout -q --detach "$BASE"
git -C "$P" update-ref refs/remotes/origin/main "$BASE"
git -C "$P" apply "$ISSUE/prototype.patch"
mkdir -p "$P/z-nile/.tracker/issues/c0293"
cp -R "$ISSUE/acceptance" "$ISSUE/check.sh" "$P/z-nile/.tracker/issues/c0293/"
# the commit identity is a one-off (-c): the runner refuses a repository whose own config holds a fixture identity
G=(git -C "$P" -c user.name=c0293-mutants -c user.email=c0293-mutants@example.invalid)
"${G[@]}" add -A
"${G[@]}" commit -qm "prototype c0293"
A="$P/z-nile/.tracker/issues/c0293/acceptance"
restore() {
  git -C "$P" checkout -q -- . && git -C "$P" clean -qfd -- pickman arcade portal snake invaders asteroids z-nile/tests >/dev/null
  git -C "$P" update-ref refs/remotes/origin/main "$BASE" # M18 deletes it
}
run() { # run <label> <mutate command> <spec file> [env]
  local label=$1 mutate=$2 file=$3 envv=${4:-}
  restore
  (cd "$P" && bash -c "$mutate")
  local out
  out=$(cd "$P/z-nile" && env $envv lune run tests/run -- "$file" 2>&1 || true)
  if grep -qE '[1-9][0-9]* failed' <<<"$out" && ! grep -qE 'could not load|syntax error' <<<"$out"; then
    echo "KILLED $label: $(grep -m1 -E '^\s+/.*spec:[0-9]+:' <<<"$out" | sed -E 's/^\s+[^ ]*spec:[0-9]+: //' | cut -c1-140)"
  else
    echo "SURVIVED $label: $(grep -m3 -E 'FAIL|could not load|syntax|error|refus' <<<"$out" | cut -c1-200 | tr '\n' '|')"
  fi
}
CARRY=ZN_C0293_CARRY=1
run M1-zz-row-left "printf '\n| \`z-nile/skills/zz-test/SKILL.md\` | writing specs |\n' >> AGENTS.md" "$A/root.spec.luau"
run M2-map-drops-asteroids "perl -pi -e 's/, \`invaders\/\` and \`asteroids\/\`\./ and \`invaders\/\`./' AGENTS.md" "$A/root.spec.luau"
run M3-processes-reworded "perl -pi -e 's/through \`.\/zn run --time <seconds> -- <command>\`: it stops/through .\/zn run: it stops/' AGENTS.md" "$A/root.spec.luau" $CARRY
run M4-rules-reordered "perl -0pi -e 's/(\*\*Subagents:\*\*[^\n]*\n)\n(\*\*Processes:\*\*[^\n]*\n)/\$2\n\$1/' AGENTS.md" "$A/root.spec.luau" $CARRY
run M5-claude-md-wrong-import "printf '@../AGENTS.md\n' > snake/CLAUDE.md" "$A/homes.spec.luau"
run M6-arcade-test-row-missing "perl -ni -e 'print unless /arcade-test/' arcade/AGENTS.md" "$A/homes.spec.luau"
run M7-root-rule-copied-into-home "grep '^\*\*Subagents:\*\*' AGENTS.md >> pickman/AGENTS.md" "$A/homes.spec.luau"
run M8-root-keeps-pickman-sentence "printf '\nA first-person Pac-Man clone for Roblox.\n' >> AGENTS.md" "$A/homes.spec.luau"
run M9-setup-old-line "git show $BASE:SETUP.md > SETUP.md" "$A/setup.spec.luau"
run M10-harvest-dropped-from-zz-execute "perl -pi -e 's/\*\*Harvest the round\*\*/Harvest the round/' z-nile/skills/zz-execute/SKILL.md" "$A/restated.spec.luau"
run M11-c0115-override-missing "git show $BASE:z-nile/tests/acceptance/c0115/docs.spec.luau > z-nile/tests/acceptance/c0115/docs.spec.luau" "tests/acceptance/c0115/docs.spec.luau"
run M12-c0184-override-reads-root "perl -pi -e 's/line\(read\(\`\{p\.name\}\/AGENTS\.md\`\)/line(read(\"AGENTS.md\")/' z-nile/tests/acceptance/c0184/docs.spec.luau" "tests/acceptance/c0184/docs.spec.luau"
run M14-temp-rule-copied-into-home "printf '\n**Temporary trees live in \`.cache/.tmp/\`, never in the system temp folder.**\n' >> snake/AGENTS.md" "$A/homes.spec.luau"
run M15-c0115-case-gutted "perl -ni -e 'print unless /at\(agents, /' z-nile/tests/acceptance/c0115/docs.spec.luau" "$A/narrowed.spec.luau" $CARRY
run M16-c0172-digest-not-updated "git show $BASE:z-nile/tests/acceptance/c0172/narrowed.spec.luau > z-nile/tests/acceptance/c0172/narrowed.spec.luau" "tests/acceptance/c0172/narrowed.spec.luau"
run M18-merge-base-unreachable "git update-ref -d refs/remotes/origin/main" "$A/root.spec.luau" $CARRY
# M13 (AC6): a promoted spec outside the Overrides changes, committed; the check.sh's own function judges it
restore
echo '-- mutant' >> "$P/z-nile/tests/acceptance/c0117/docs.spec.luau"
"${G[@]}" commit -qam "mutant M13"
out=$(cd "$P" && bash z-nile/.tracker/issues/c0293/check.sh 2>&1 | grep -A2 'AC6:' || true)
if grep -q 'FAIL.*AC6' <<<"$out" && grep -q 'c0117/docs.spec.luau' <<<"$out"; then
  echo "KILLED M13-unlisted-promoted-spec-changed: $(sed -n 2p <<<"$out" | cut -c1-140)"
else
  echo "SURVIVED M13-unlisted-promoted-spec-changed: $out"
fi
