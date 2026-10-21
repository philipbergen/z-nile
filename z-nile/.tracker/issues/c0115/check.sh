#!/usr/bin/env bash
# Acceptance checks for c0115. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home: the root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0115 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0115"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: skills live in z-nile/skills and <project>/skills; ./zn skills links each from .claude/skills and refuses bad folders" lune run tests/run -- "$A/skills.spec.luau"
# AC2 runs c0115's own `skills --check` and its changed `--plan` in a plain clone of HEAD under .cache (never
# `git worktree add`, which writes the real .git): a wrong --check that writes then fails the clean-status assertion
# and the "ok" line, and the committed links are what is checked, as CI's fresh checkout sees them.
links_check() {
  local copy="$PWD/.cache/c0115-ac2"
  mkdir -p "$PWD/.cache" && rm -rf "$copy" && git clone -q --no-hardlinks "$PWD" "$copy" || return 1
  (
    cd "$copy" || exit 1
    out=$(./zn skills --check) || { echo "$out"; exit 1; }
    [[ $out == *"one link each, ok"* ]] || { echo "skills --check said: $out"; exit 1; }
    z-nile/check.sh --plan | grep -qx "skills: .claude/skills" || { echo "no skills: line in --plan"; exit 1; }
    [[ -z $(git status --porcelain) ]] || { echo "the copy changed:"; git status --porcelain; exit 1; }
  ) || return 1
  rm -rf "$copy"
  grep -qxF '[[ -d z-nile/skills ]] && par_start "skills (./zn skills --check)" ./zn skills --check' z-nile/check.sh
}
check "AC2: the committed links pass ./zn skills --check in a clean copy, which it leaves unchanged, and the gate runs it" links_check
check "AC3: the eleven skills are renamed into their folders, nothing old is left, and z-raft is not made here" \
  bash -c 'lune run tests/run -- "$1" && test -z "$(git ls-files -- z-nile/skills/z-raft .claude/skills/z-raft)"' _ "$A/layout.spec.luau"
check "AC4: no live file names an old skill or cites an old lesson id, and no code or spec reads through a .claude/skills link" lune run tests/run -- "$A/absence.spec.luau"
check "AC5: lessons live in the real skill folders under the new ids, and no ledger names an old id" lune run tests/run -- "$A/lessons.spec.luau"
check "AC6: the real tree's lessons and harvest ledgers check clean, every finding covered" \
  bash -c './zn lessons --check && ./zn lessons --uncovered R0040 R0042'
check "AC7: a prompt inlines z-nile's step skills, then its own project's, with that project's lessons only" lune run tests/run -- "$A/prompt.spec.luau"
check "AC8: the skills, AGENTS.md, SETUP.md, the usage, the board and the engine's messages use the new names" \
  lune run tests/run -- "$A/docs.spec.luau" tests/acceptance/c0042/model.spec.luau tests/acceptance/c0107/views.spec.luau tests/acceptance/c0069/prompt.spec.luau
check "AC9: z-nile/README.md opens with the picture of the five parts, then names every skill and the three checklists" lune run tests/run -- "$A/readme.spec.luau"
check "AC10: the guard, structure, lessons-paragraph and check-path specs pass in both homes" \
  bash -c 'lune run tests/run -- tests/tooling/repo-fence.spec.luau tests/meta/architecture.spec.luau tests/acceptance/c0111/skill-docs.spec.luau tests/acceptance/c0120/check-paths.spec.luau && cd pickman && lune run tests/run -- tests/meta/architecture.spec.luau tests/meta/fence.spec.luau'
check "AC11: the real tracker audits clean" ./zn audit
check "AC12: as of the last fetch, nothing but this raft holds the skill folders or their links: no other raft active, no branch or worktree changing them" \
  ./zn busy .claude/skills z-nile/skills pickman/skills

# AC13 reads the branch's own commits since it left origin/main (git reads only): exactly one commit whose subject
# starts "c0115: move the skills", holding only R100 renames, and no other commit of the range renaming a skill file.
# It is a branch check (`./zn check`, `done`); once the PR is squashed into main the range is empty, and it fails.
moves_only() {
  local base moves bad c
  base=$(git merge-base origin/main HEAD) || return 1
  moves=$(git log --format=%H --grep='^c0115: move the skills' "$base..HEAD")
  if [[ $(printf '%s\n' "$moves" | grep -c .) != 1 ]]; then echo "want one moves commit since $base, got: ${moves:-none}"; return 1; fi
  bad=$(git show -M --find-renames=100% --name-status --format= "$moves" | grep -v '^R100' || true)
  if [[ -n $bad ]]; then echo "the moves commit is not renames only: $bad"; return 1; fi
  for c in $(git rev-list "$base..HEAD"); do
    [[ $c == "$moves" ]] && continue
    if git show -M --name-status --format= "$c" | grep -E '^R[0-9]+' | grep -qE $'\t(\.claude/skills|z-nile/skills|pickman/skills)/'; then
      echo "$c renames a skill file outside the moves commit"; return 1
    fi
  done
}
check "AC13: the skills move is one renames-only commit, and no other commit of the branch renames a skill file" moves_only

finish
