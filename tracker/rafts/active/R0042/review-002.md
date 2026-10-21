# Review 002: R0042 (code mode)
Inputs: `git diff origin/main...HEAD` at b37ab12 (origin/main b20febd after `tracker.sh sync --fetch`), and the fix delta `git diff 602ec0a..HEAD` (602ec0a added `review-001.md`); `review-001.md`, `refute-001.md`, `harvest.md`; `tracker/rafts/active/R0042/R0042.md`, `tracker/issues/active/c0111/c0111.md`, `tracker/issues/active/c0119/c0119.md`, their `check.sh` files and acceptance specs; `scripts/tracker.sh lessons --when build --full` and `--skill review --full`.
Dropped from review-001: F1, F2, F3 (all three fixed in e3f44f4 as the refute says; checked below).
Runs: `scripts/check.sh --full` GATE PASSED (1821 passed, 0 failed, 262 spec files); `tracker.sh check c0111` 11/11; `check c0119` 4/4; `check R0042` 7/7; `lessons --check` ok (21 lessons, 117 harvest entries); `lessons --uncovered R0042` covered. The sequestration diff (`--find-renames=100%` over `check.sh` and `acceptance/**`) lists nothing. The working tree was clean after every run.

Fix delta, item by item:
- review-001 F1: the rewritten How to apply now agrees with `trail.read` (current id only, `--no-renames`, the life starts at the newest commit that changed `tracker/compaction.txt` together with the document, and gets marked) and with the marker text in `cmd.capture` (`(history before <sha> not followed: …)`). Its `created:` example matches `main.luau:3403`. The body no longer contradicts the check line.
- review-001 F3: both `trail.luau` comments now match `changes`, which sets `c.id` to the current id.
- review-001 F2: `lessons.load` skips names starting with `.`. `load` is the only reader of `lessons/` folders (the prompt's `buildLessons` and `cmd.lessons` both go through it), so nothing else needs the same rule. The lessons-cli case that writes `notes.txt` still pins the "not a lesson file" report for every other name. The deviation is recorded in c0111's Verification log. The skip itself is untested (F1 below).

### F1 [low] The hidden-file skip added for review-001 F2 has no spec
Where: `scripts/tracker/lessons.luau:546-547` (`load`)
Evidence: No spec writes a dotfile into a `lessons/` folder. If the `string.sub(name, 1, 1) == "."` branch were deleted, every spec would still pass, and a Finder `.DS_Store` would turn `lessons --check` red again. The refute checked this by hand once.
Critique: This is a small, recorded deviation, and the opposite direction (skipping too much) is still pinned by the `notes.txt` case. So the risk is only a silent regression of a convenience fix. The tempting fix is a new case in the sequestered `lessons-cli.spec.luau`, which code mode may not ask for.
Consequences: a promoted spec outside the sequestered files is the author's own, so it's allowed. It needs a fixture under `.cache`, like the existing cases.
Recommendation: add a pure case in a non-sequestered spec under `tests/` (for example `tests/tooling/lessons-load.spec.luau`) that runs `lessons.load` on a `.cache` fixture holding one valid lesson, a `.DS_Store` and a `notes.txt`. Assert that the problems list names only `notes.txt` and that the lesson loads. Or leave it as is and note in the Verification log that the skip was checked only by hand.

## Judged criteria (code mode only)
- JC1: pass. Since review-001 the harvest has added no new lesson: review-001 F1 and F3 map to the existing `ticket-prep/restated-rules-move-together`, which fits, since both were text left behind when the rule changed. F2 is a one-off, which is right for a host quirk. My review-001 ruling on all 19 lessons from the R0040 and R0042 harvests still holds: each `check` is a question another raft's draft or diff could fail, and each body gives the rule, a Why with its incident, and a How to apply. The one defect I found then (the stale How to apply of `tracker/item-history-spans-moves-and-compaction`) is fixed, and that lesson is now general (read every folder, never cross an id change, mark the result, date by a field no renumber rewrites). None of the lessons makes sense only for this raft.

Verdict: approve
