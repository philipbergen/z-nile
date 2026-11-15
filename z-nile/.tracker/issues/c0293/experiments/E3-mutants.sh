#!/usr/bin/env bash
# c0293 mutation check: apply each mutant to the prototype worktree, run the row's check, expect a FAIL on an
# assertion, then restore the prototype. Run from the prototype worktree's top.
set -uo pipefail
P="$(pwd -P)"
A="$P/z-nile/.tracker/issues/c0293/acceptance"
restore() { git -C "$P" checkout -q -- . && git -C "$P" clean -qfd -- pickman arcade portal snake invaders asteroids >/dev/null; }
spec() { # spec <file> [env]: run one c0293 spec from z-nile's home, print its summary line
  (cd "$P/z-nile" && env ${2:-} lune run tests/run -- "$@" 2>&1) | grep -E 'passed,|could not load|attempt to|syntax' | tail -2
}
run() { # run <label> <mutate command> <spec file> [env]
  local label=$1 mutate=$2 file=$3 envv=${4:-}
  restore
  bash -c "$mutate"
  local out
  out=$(cd "$P/z-nile" && env $envv lune run tests/run -- "$file" 2>&1)
  if grep -qE '[1-9][0-9]* failed' <<<"$out" && ! grep -qE 'could not load|syntax error' <<<"$out"; then
    echo "KILLED $label: $(grep -m1 -E '^\s+/.*spec:[0-9]+:' <<<"$out" | sed -E 's/^\s+[^ ]*spec:[0-9]+: //' | cut -c1-140)"
  else
    echo "SURVIVED $label: $(tail -1 <<<"$out")"
  fi
}
run M1-zz-row-left "printf '\n| \`z-nile/skills/zz-test/SKILL.md\` | writing specs |\n' >> AGENTS.md" "$A/root.spec.luau"
run M2-map-drops-asteroids "perl -pi -e 's/, \`invaders\/\` and \`asteroids\/\`\./ and \`invaders\/\`./' AGENTS.md" "$A/root.spec.luau"
run M3-processes-reworded "perl -pi -e 's/through \`.\/zn run --time <seconds> -- <command>\`: it stops/through .\/zn run: it stops/' AGENTS.md" "$A/root.spec.luau" ZN_C0293_CARRY=1
run M4-rules-reordered "perl -0pi -e 's/(\*\*Subagents:\*\*[^\n]*\n)\n(\*\*Processes:\*\*[^\n]*\n)/\$2\n\$1/' AGENTS.md" "$A/root.spec.luau" ZN_C0293_CARRY=1
run M5-claude-md-wrong-import "printf '@../AGENTS.md\n' > snake/CLAUDE.md" "$A/homes.spec.luau"
run M6-arcade-test-row-missing "perl -ni -e 'print unless /arcade-test/' arcade/AGENTS.md" "$A/homes.spec.luau"
run M7-root-rule-copied-into-home "grep '^\*\*Subagents:\*\*' AGENTS.md >> pickman/AGENTS.md" "$A/homes.spec.luau"
run M8-root-keeps-pickman-sentence "printf '\nA first-person Pac-Man clone for Roblox.\n' >> AGENTS.md" "$A/homes.spec.luau"
run M9-setup-old-line "git -C '$P' show origin/main:SETUP.md > SETUP.md" "$A/setup.spec.luau"
run M10-harvest-dropped-from-zz-execute "perl -pi -e 's/\*\*Harvest the round\*\*/Harvest the round/' z-nile/skills/zz-execute/SKILL.md" "$A/restated.spec.luau"
run M11-c0115-override-missing "git -C '$P' show origin/main:z-nile/tests/acceptance/c0115/docs.spec.luau > z-nile/tests/acceptance/c0115/docs.spec.luau" "tests/acceptance/c0115/docs.spec.luau"
run M12-c0184-override-reads-root "perl -pi -e 's/line\(read\(\`\{p\.name\}\/AGENTS\.md\`\)/line(read(\"AGENTS.md\")/' z-nile/tests/acceptance/c0184/docs.spec.luau" "tests/acceptance/c0184/docs.spec.luau"
restore
# M13 (AC6): a promoted spec outside the Overrides changes, committed; the check.sh's own function judges it
echo '-- mutant' >> z-nile/tests/acceptance/c0117/docs.spec.luau
git -C "$P" commit -qam "mutant M13 (local)"
out=$(bash "$P/z-nile/.tracker/issues/c0293/check.sh" 2>&1 | grep -A2 'AC6:')
git -C "$P" reset -q --hard HEAD~1
if grep -q '^FAIL  AC6' <<<"$out" && grep -q 'c0117/docs.spec.luau' <<<"$out"; then
  echo "KILLED M13-unlisted-promoted-spec-changed: $(sed -n 2p <<<"$out" | cut -c1-140)"
else
  echo "SURVIVED M13-unlisted-promoted-spec-changed: $out"
fi
restore
git -C "$P" status --short | head -5
