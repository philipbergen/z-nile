# Review 003: c0134 (design mode)
Inputs: prep `prep-c0131-accept-header` at ac1a6478 (c0134.md, check.sh, acceptance/{header.spec,split,body}.luau, design-review-002.md, design-refute-002.md, harvest.md); `./zn lessons --when design`. In a scratch clone of ac1a6478 (origin a scratch bare copy) I applied the Design's header to `z-nile/tests/acceptance/c0131/accept.spec.luau` exactly: `./zn check c0134` printed `3/3 criteria passed`, and `./zn promote-check c0134` printed `promote-check OK`.
Dropped from review-002: F1 (fixed: the changeable part is now defined positively, and every other byte is compared), F2 (fixed: the lesson's check was widened).

Spot runs. Each one mutates the fixed file and then runs AC2's own diff, `diff <(git show $base:… | lune run body.luau) <(lune run body.luau < file)`:
- M7 line 1 replaced by `_G.m=true`: red. M8 line 1 `--!nonstrict`: red. M9 `--[[c0134]] _G.m = true` inside the run: red. M10 `_G.m = true` appended with no newline: red.
- Edges I added: a `--[[` line opening a block inside the run (its `]]` two lines later): red. Empty file: red. Final newline dropped: red. A `-- ]] _G.m = true` line in the run: green, which is correct, because no block is open there (line 1 is compared byte for byte, so nothing before the run can open one) and the line is a line comment. A `-- x\r` line: green, also a comment. One more plain `-- ` line at the end of the header: green, which is correct (AC1 judges the header).

The mechanism holds. Every byte is either in a run of plain line comments, which cannot hold code in Luau, or compared.

### F1 [medium] AC2 passes when `body.luau` can't run: both process substitutions print nothing, and `diff` of two empty streams succeeds
Where: check.sh `body_unchanged` (`diff <(… | lune run "$A/body.luau") <(lune run "$A/body.luau" <"$f")`).
Evidence: in the clone I appended `_G.m = true` to accept.spec.luau and ran AC2's diff with `A=/nonexistent`. lune printed `Failed to resolve script at path /nonexistent/body (NotFound)` twice, and the diff exited 0: `AC2 GREEN with a missing body.luau and a code line appended`. Bash ignores a process substitution's exit status, so any failure of `lune run body.luau` turns AC2 green whatever the file holds. That includes a moved `$A` after promotion, a broken `require("./split")`, a lune or `@lune/stdio` change, or a crash.
Critique: lesson zz-test/no-vacuous-pass: "not run" must differ from "unchanged". AC2 is the only check that the change is comment-only. The tempting fix is `set -o pipefail`, which does not cover process substitution.
Consequences: the two bodies must be produced by commands whose status is checked. An empty body is a legitimate output only for an empty file, so "both empty" can't serve as the error signal.
Recommendation: write each body to a file under `.cache/c0134-ac2/` (or a variable) with its status checked: `old=$(git show "$base:z-nile/$f" | lune run "$A/body.luau") || { echo "cannot cut the base's body"; return 1; }` (with `set -o pipefail` inside the function for the `git show` half), the same for the working file, then `[[ "$old" == "$new" ]]`. A variable drops trailing newlines, so append a sentinel in body.luau or compare files. Add a Rules row with the mutant "body.luau fails (a wrong `$A`)", run, expecting AC2 red.
Lesson: zz-test/no-vacuous-pass

### F2 [low] AC2's base comes from the local `refs/remotes/origin/main`, which one `update-ref` moves to HEAD, and then AC2 reports "nothing to compare"
Where: check.sh `body_unchanged` (`base=$(git merge-base origin/main HEAD)`); E3 ("which the branch can't move").
Evidence (reasoned, not run): `git update-ref refs/remotes/origin/main HEAD` in the execution worktree makes the merge-base HEAD. AC2 then prints `base is HEAD: nothing to compare` and passes over any body edit. A code reviewer's `./zn sync --fetch` resets the ref (the fetch refspec is forced), so only an unreviewed local run is fooled, which makes this low.
Critique: lesson zz-review/sequestration-reference-not-a-ref (c0120 review 008 F1: the local origin/main ref is in the author's control). E3's claim that the branch can't move the base is not true for the local ref.
Consequences: reading main's tip from `git ls-remote origin refs/heads/main` needs the network and the tip fetched (as c0115's `trusted-base` does), and refuses offline.
Recommendation: either take the tip from `git ls-remote origin refs/heads/main`, require `git cat-file -e` of it, and refuse when it can't be read, or correct E3's sentence to say that the local ref can be moved and that the code review's fetch is what restores it. The first is the lesson's rule. The second is acceptable for a comment-only chore if the author says so.
Lesson: zz-review/sequestration-reference-not-a-ref

Scope: the capture's comment-only header fix is met by AC1 and AC2. Nothing dropped.

Candidate lessons (for the lead): fold into zz-test/no-vacuous-pass: "`diff <(a) <(b)` ignores both commands' status: two failed producers compare equal; check: is every producer of a compared text's exit status checked?"

Verdict: changes
