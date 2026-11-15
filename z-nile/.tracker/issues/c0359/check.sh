#!/usr/bin/env bash
# Acceptance checks for c0359. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0359 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0359"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# has <file> <literal>...: every literal is in the file, else name the first missing one
has() {
  local f=$1 w
  shift
  [[ -f $f ]] || { echo "no $f"; return 1; }
  for w in "$@"; do grep -qF -- "$w" "$f" || { echo "$f does not say: $w"; return 1; }; done
}
# lacks <file> <literal>...: no literal is in the file
lacks() {
  local f=$1 w
  shift
  [[ -f $f ]] || { echo "no $f"; return 1; }
  for w in "$@"; do ! grep -qF -- "$w" "$f" || { echo "$f still says: $w"; return 1; }; done
}
export -f has lacks
export HERE
# the folder names, kept out of literal paths (a check.sh names only paths that exist from its home: c0120/check-paths)
Z=z-nile GH=.github
export Z GH
# the published main AC6 compares against, printed outside `check` (a passing command's output is hidden): a swapped
# origin is review's to catch
echo "AC6 base: $(git -C "$ZN_ROOT" ls-remote --get-url origin) refs/heads/main"

check "AC1: the static workflow (static.yml) is one job, static, on every pull request event with no filter, condition or secret, that checks out, installs the pinned tools and runs the gate script with --lint" \
  lune run tests/run -- "$A/workflow.spec.luau"
check "AC2: the committed static ruleset (static.json) requires the check static from GitHub Actions on the default branch, not strict, with the repository admin role as its one bypass, and that context is static.yml's job" \
  lune run tests/run -- "$A/ruleset.spec.luau"
check "AC3: dispatch.lintable is true for a Lua or Luau source and for TOML, YAML and dot files, in any case, and false for documents, scripts, JSON and .luau.txt reference texts" \
  lune run tests/run -- "$A/lintable.spec.luau"
check "AC4: the gate script with --lint runs the format and lint stages alone, with the real tools, over every project's folders, never narrowed; a diff or a warning alone fails it naming the file; both stages report; --plan prints only their folders; it writes nothing outside .cache" \
  lune run tests/run -- "$A/lint.spec.luau"
check "AC5: the dispatcher's prep and raft gates refuse a PR whose merge with today's main fails the stages, naming the file, after the shape judgement (a PR's own gate script never runs); a clean PR merges pinned to its head; a PR with no lintable path is not linted; no scratch tree is left" \
  lune run tests/run -- "$A/gate.spec.luau"
check "AC6: the promoted c0172 deploy spec is its merge base plus only c0359's override (the one case renamed, one comment line, the list widened to deploy.yml and static.yml), byte for byte" \
  python3 "$A/narrow.py" "$ZN_ROOT"
check "AC7: GitHub enforces the active ruleset static on main: its required_status_checks rule names exactly the committed checks and is not strict" \
  python3 "$A/live.py" "$ZN_ROOT"
check "AC8: the lesson zz-rules/hand-merge-runs-static-stages says GitHub's checks are not the gate, names the incident (2026-11-15, the four PRs, #433, c0292's E3, the user's words), the gate script's --lint, the required checks, a PR that changes the checker and a red main, and is read in both modes with its check question" \
  bash -c 'L=skills/zz-rules/lessons/hand-merge-runs-static-stages.md
    grep -qx "when: both" "$L" || { echo "$L is not when: both"; exit 1; }
    grep -qE "^check: .*$Z/check.sh --lint.*\?\$" "$L" || { echo "$L has no check question naming the gate script with --lint"; exit 1; }
    has "$L" "GitHub'"'"'s checks are not the gate" "2026-11-15" "#397, #399, #408, #417" "#433" "c0292'"'"'s E3" \
      "Learn a lesson from this and make sure it can'"'"'t happen again" "merge \`origin/main\`, run \`$Z/check.sh --lint\`" "never with \`--admin\`" \
      "check that \`gh pr checks <pr> --required\` passes" "passes its own copy" "\`gh run rerun\` judges the old merge"'
check "AC9: the lesson has its source (a note in this issue's harvest.md) and ./zn lessons --check and --uncovered c0359 pass" \
  bash -c 'grep -qE "^- note .*: (.*, )?zz-rules/hand-merge-runs-static-stages(,|\$)" "$HERE/harvest.md" || { echo "harvest.md has no note naming zz-rules/hand-merge-runs-static-stages"; exit 1; }
    "$ZN_ROOT/zn" lessons --check && "$ZN_ROOT/zn" lessons --uncovered c0359'
check "AC10: zz-rules says main requires the static check, that it is a floor and not the verification, that a hand merge runs the gate script with --lint first (Landing a change step 3, naming the lesson), and that done's landing push bypasses only after its own gate, that gh pr checks --required must pass, the known limit, and that the chain's gates lint the merge; it no longer says the server stops nothing or that a merge never bypasses" \
  bash -c 'S=skills/zz-rules/SKILL.md
    has "$S" "\`main\` requires one check, \`static\`" "It is a floor, not the verification" "That is the verification. A merge does not read GitHub Actions." \
      "its merge with today'"'"'s \`main\` passes the gate'"'"'s format and lint stages (\`$Z/check.sh --lint\`" \
      "the tracker'"'"'s own pushes to \`main\` and \`./zn done\`'"'"'s landing push need it, and \`./zn done\` lands a raft only after its own affected gate" \
      "\`gh pr checks <pr> --required\` must pass too" "Known limit: a pull request that changes" || exit 1
    lacks "$S" "until then the server stops nothing" "may have no branch protection" "green CI" "a merge never does" || exit 1
    step3=$(awk "/^## Landing a change/{f=1} /^## Merging/{f=0} f" "$S" | grep "^3\. ")
    printf "%s\n" "$step3" | grep -qF "run \`$Z/check.sh --lint\` there until it exits 0, and check that \`gh pr checks <pr> --required\` passes" || { echo "Landing a change step 3 lacks the hand-merge sentence"; exit 1; }
    printf "%s\n" "$step3" | grep -qF "(lesson zz-rules/hand-merge-runs-static-stages)" || { echo "Landing a change step 3 does not name the lesson"; exit 1; }'
check "AC11: zz-test's gate table lists the gate script's --lint, and the gate script's usage names it" \
  bash -c 'has skills/zz-test/SKILL.md "| \`$Z/check.sh --lint\` | the format and lint stages alone" "(c0359) |" &&
    has check.sh "| --static | --lint]" "# --lint runs the format and lint stages alone, over every project (never narrowed by the change)"'
check "AC12: SETUP says a merge waits for the required static check and how the admin posts, reads and removes the ruleset and re-runs an old PR's check (and every PR's after a red main), and no longer says deploy.yml is the only workflow" \
  bash -c 'F="$ZN_ROOT/SETUP.md"
    has "$F" "Verification is local." "A merge waits for one Actions result, the required \`static\` check" \
      "gh api -X POST repos/{owner}/{repo}/rulesets --input $GH/rulesets/static.json" "gh api repos/{owner}/{repo}/rules/branches/main" \
      "gh api -X DELETE repos/{owner}/{repo}/rulesets/<id>" "push to its branch (a merge of \`origin/main\` does), or close and reopen it" \
      "When \`main\` itself fails the stages, every pull request'"'"'s \`static\` fails until \`main\` is fixed" || exit 1
    lacks "$F" "\`$GH/workflows/deploy.yml\` is the only workflow." "a merge does not wait for an Actions result"'
check "AC13: c0292's lesson z-design/prep-specs-pass-format-and-lint no longer says the prep gate merges on CI that runs no gate, and says the gates run the two stages on the merge (c0359)" \
  bash -c 'L=skills/z-design/lessons/prep-specs-pass-format-and-lint.md
    lacks "$L" "the prep gate merges on CI, which runs no gate" &&
    has "$L" "Under \`./zn dispatch\` the prep and raft gates run these two stages on the merge and hold a pull request that fails them, and GitHub requires the same \`static\` check on every merge into \`main\` (c0359)."'
check "AC14: the dispatcher specs the gate change could break still pass: c0117's control CLI and the dispatcher's guards (both slow-tier, so no gate runs them)" \
  lune run tests/run -- tests/acceptance/c0117/control-cli.spec.luau tests/tooling/dispatch-guards.spec.luau
check "AC15: the selector's input list declares the files outside z-nile/ each promoted c0359 spec reads (the two GitHub folders, the root's format, lint and Luau settings)" \
  bash -c 'S=tests/acceptance/c0359; T=$(printf "\t")
    for line in "$S/workflow.spec.luau$T$GH/workflows/" "$S/ruleset.spec.luau$T$GH/rulesets/" "$S/ruleset.spec.luau$T$GH/workflows/" \
      "$S/lint.spec.luau${T}stylua.toml" "$S/lint.spec.luau${T}selene.toml" "$S/lint.spec.luau$T.luaurc" \
      "$S/gate.spec.luau${T}stylua.toml" "$S/gate.spec.luau${T}selene.toml"; do
      grep -qxF -- "$line" tests/inputs.tsv || { echo "tests/inputs.tsv lacks: $line"; exit 1; }
    done'

finish
