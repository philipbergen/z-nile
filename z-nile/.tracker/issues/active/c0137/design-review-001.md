# Review 001: c0137 (design mode)
Inputs: prep `prep-finished-claude-scans` d02358de (c0137.md, check.sh, acceptance/scans.spec.luau, and the three finished check.sh files it edits: `git diff origin/main...HEAD`); capture 2af9a1b2; `./zn lessons --when design --full`. Scratch clone of d02358de (scratchpad `dr-chores-2/c0137`).

Checked and holding:
- scans.spec + c0120's finished.spec on the prep tree: `12 passed, 0 failed, 2 spec files`. finished.spec does not flag the new operands, none of which resolved before the move.
- scans.spec really fails on the vacuous form. With c0067's check.sh put back to origin/main's text: `FAIL … no rewritten line reads .claude from z-nile/`, `FAIL … each grep is clean … and red for a phrase in each skills folder`, `FAIL … the make-prompt test …`, `3 passed, 3 failed`.
- The fifth line named in the Problem, c0069:41, is gone (c0069's check.sh holds no `./zn launch` grep over `.claude`).
- Not scanning `../.claude` is right. On origin/main it tracks only `settings.json` and the 14 skill links (`git ls-tree -r --name-only origin/main -- .claude`), and `grep -r` would walk `.claude/worktrees` while not following the links.
- A search for every `.claude` form in finished and live check.sh files (`git grep -nE '\.claude' -- '*/.tracker/*/done/*/check.sh' '*/.tracker/*/active/*/check.sh' '*/.tracker/*/check.sh'`) finds no other recursive scan. The remaining hits are reads of named files through a link (c0005:41/48, c0035:5, c0040:7, c0046:38, c0053:37–45, c0058:69, c0084:45, R0025:40–48, which `grep` follows because they name a file), labels (c0113, c0115, c0137), and c0115's root-relative `./zn busy`/regex lines.
- On the real home today all three rewritten greps exit 1 (no match, no missing operand).

### F1 [medium] the promoted guard can't tell "an operand is missing" from "clean", so the next folder move makes these lines vacuous again and scans.spec stays green
Where: the four rewritten lines (each still ends `|| true`); scans.spec "in the real home every line finds nothing" (compares only `$bad`'s stdout with `""`); Maintainability ("the spec pins each line's behaviour").
Evidence: run from a home where `skills` is missing and the phrase sits in a moved skills folder, the rewritten c0044 line prints `grep: skills: No such file or directory` and `bad=[]`, so the check passes. In the same home with the phrase in `../pickman/skills`, it finds it. This is exactly the c0120 failure mode, now for `skills`, `../pickman/skills`, `scripts` or `./templates`. The real-home case would return `""` and pass. The make-prompt test is an absence test of three paths, and it passes the same way if those folders move.
Critique: lesson zz-test/no-vacuous-pass says "not found" must differ from "checked and clean". The design fixes today's operands but leaves the mechanism that hid the defect, and the promoted spec is the only place that can catch it again (the finished lines must not change beyond their operands). The tempting fix is dropping `|| true` from the finished lines. That edits more of a finished file than G1 covers and turns a grep with no match (exit 1) red.
Consequences: the spec must parse the operands out of each line, or run the grep part without `|| true`. That only needs the line's own text, which `line()` already finds.
Recommendation: in the real-home case, run each grep line with stderr captured and require it to be empty (grep reports a missing operand there), or strip `|| true` and require exit 1 rather than 2. For the make-prompt line, require that the folders it tests (`skills`, `../pickman/skills`, `../.claude/skills`) exist in the real home. Add a Rules row with mutant "an operand renamed to a folder that does not exist (e.g. `skillz`)", run, expecting red. In a fixture case, delete `z-nile/skills` and expect the line to be reported as not checking, not as clean.
Lesson: zz-test/no-vacuous-pass

### F2 [low] the `scripts` operand and `.claude/settings.json` also changed meaning at c0120, and the Design doesn't say why it leaves them
Where: Design ("`.claude` itself now holds only `settings.json`, the links …"); the four lines' `scripts` operand.
Evidence: before c0120 these lines ran from the repository root, so `scripts` was the root `scripts/`, which still exists on origin/main (`hooks/`, `lib/`, `setup.sh`, `tracker.sh`, `tracker/`, …). From `z-nile/` the lines now read `z-nile/scripts` (`check.sh`, `tracker.sh`). Likewise `.claude` covered `settings.json` (which holds the `Bash(./zn …)` allow list R0025's RC1 would care about). Today neither holds a banned phrase: `grep -rnF -e "<ID>-<slug>" -e "<id>-<slug>" -e "-slug.md" -e "-<slug>.md" -e pbcopy -e clipboard -e make-prompt -e "./zn launch" scripts .claude/settings.json` from the root prints nothing.
Critique: the capture's Solution is "what they read before c0120's move". Leaving these out may be fine, but it is a choice the document doesn't record.
Consequences: adding `../scripts ../.claude/settings.json` is the same kind of operand edit G1 already covers. Leaving them out needs one sentence.
Recommendation: either add `../scripts` and `../.claude/settings.json` to the three greps (and seed them in scans.spec's fixture, with a planted phrase case each), or add a sentence saying why the root scripts and settings are no longer these checks' concern. Ask the user if unsure, since it widens what finished checks guard.

Scope: the capture's four lines (and the Problem's later fifth, already removed by c0115) each have a Design and AC1. Nothing was dropped.

Candidate lessons (for the lead):
- zz-test: a fix for a vacuous check also guards the mechanism that hid it (here `|| true` swallowing grep's exit 2), because otherwise the next move re-creates it silently. Check: after this fix, does removing one operand folder turn some check red?

Verdict: changes
