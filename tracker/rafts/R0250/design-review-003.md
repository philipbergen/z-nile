# Review 003: R0250 (design mode)
Inputs: 6bde539 (the round-2 answer), unchanged for every reviewed path at 459754b (`git diff 6bde539 HEAD` over the four members, R0250, `tests`, `.github`, `scripts`, `.claude` and `tracker/issues/done` is empty). Reviewed: R0250.md, R0250/check.sh; c0730, c0740, c0750, c0760 (documents, check.sh, acceptance specs); `git diff origin/main -- tracker/issues/done tests/acceptance .github`; design-review-001/002 and design-refute-001/002; scripts/tracker/{main,publish,store,board}.luau, scripts/tracker.sh, .github/workflows/check.yml; promoted specs c0010 ci-workflow, c0041 worktree, c0400 cli, c0430 workstreams, c0450 override-check, c0470 spec-isolation, c0510 commands/publish; done check.sh files of c0041, c0070, c0340, c0430, c0440, c0450, c0510, R0020.
The working tree carries an uncommitted edit of R0250.md that adds c0770, c0680 and c0720 to `issues:`, which is mid-edit and outside this round. If it is meant to land, those issues need the same design pass (Whole-raft design, Order & dependencies, RCs, and a review).
Dropped from review-002: none. F1–F7 are all fixed as the refute states. I checked each fix:
- F1: a scan of every literal `.cache/<dir>` across `tests/` and the four member `acceptance/` folders finds no shared directory (`.cache/sim` excepted, as c0470 allows).
- F2: c0730 has the `check.yml` snippet, Touched modules, AC13 and the c0010 guard line. The snippet keeps c0010's literal glob inside the `workflow_dispatch` step.
- F3: `sweepStale(root)` covers every state and kind, and runs in ready, stop, sync and the refresh. ready.spec plants `.DS_Store` in `issues/c0010`, `rafts/R0010` and `issues/active/c0040`, and `.git/info/exclude` keeps `ready`'s clean check valid. `git clean` never removes tracked files, so even an unmigrated legacy-named document can't be swept.
- F4: the out-of-`done/` sub-case is consistent in every other respect (whole directory, status line only, the exact rewrite), so a target-only validator lets it through and the case fails.
- F5: RC7 copies c0510's three functions verbatim.
- F6: c0750 keeps `prompt` out of `READ_ONLY`. The guard runs before `flags()`, so the old `--stdout` argument in c0510's sandbox case still gets "repository root".
- F7: `normalize` is gone; USAGE and RC4 ban plain "launch"; E7 escalates; `sweepStale` takes a root; and the pre-ready-worktree case exists. In that case the legacy refusal ("… is active on origin/main, not prepared") has no "sync", so it kills the listed mutant.

Verification run for this round: `bash -n` on all five check.sh files; `AC_LIST=1` lists 13, 7, 6, 5 and 13 criteria; `stylua --check` and `selene` are clean on the six member specs; `make-prompt`/`tracker.sh launch`/`clipboard` greps over the RC1 and AC10 scopes find only text the design rewrites.

### F1 [medium] c0730's AC11 matches its own check.sh, and R0250's, once `done` moves them to `done/`, so c0730's and R0250's checks are permanently red on `main` after the merge
Where: tracker/issues/c0730/check.sh:65-69 (AC11, `grep -rlF "make-prompt" tracker/issues/done tracker/rafts/done --include=check.sh`); the same file at lines 41, 44, 65 and 68, and tracker/rafts/R0250/check.sh:14-15, which contain the string `make-prompt`.
Evidence:
- `cmd.done` (main.luau:1455) runs `runCheck(raft)` before it moves anything. So AC11 passes at `done` time, while no `c0730` or `R0250` directory is under `done/` yet.
- After the move, `tracker/issues/done/c0730/check.sh` and `tracker/rafts/done/R0250/check.sh` both contain `make-prompt`, in AC10's label and its `[ ! -e .claude/skills/make-prompt ]` test, and in RC1's label and grep. AC11's own grep then lists both files.
- From the merge on, `bash tracker/issues/done/c0730/check.sh` fails AC11, and `tracker.sh check R0250` fails RC0 through it.
- That is exactly the state this raft's RC5 exists to prevent for c0041, c0430, c0440 and c0450: a later raft that reruns or overrides done checks (as R0250 does here) would find c0730 red for no reason, and could not edit it during execution.
Critique: the tempting fix is to drop the `make-prompt` wording from AC10 and RC1. That weakens them, since RC1 must name the string it bans.
Consequences: any scan of `tracker/**/check.sh` for a banned token has to exclude the checks that ban it. The same applies to future rafts, but it bites only scans that include `tracker/*/done`.
Recommendation: in prep (these are still prep-time files), restrict AC11 to the five files edited in prep: `for id in c0041 c0430 c0440 c0450 c0510; do ! grep -qF make-prompt "tracker/issues/done/$id/check.sh" || …; done`. Alternatively, exclude `/c0730/check.sh` and `/R0250/check.sh` from the grep's output. Verify with a dry run that copies c0730/check.sh and R0250/check.sh under a scratch `tracker/issues/done/`/`tracker/rafts/done/` layout. No spec change is needed.

### F2 [low] c0070's done check pins wording in the `done` row and in execute-raft Phase 5, which this raft's skill rewrites may touch, and nothing names or runs it
Where: tracker/issues/done/c0070/check.sh:27-36 (AC3); .claude/skills/tracker/SKILL.md:72 (the `| done |` row: "marks the PR **ready** before its final push") and :89 ("the push starts the `pull_request` run"); .claude/skills/execute-raft/SKILL.md:98 ("marks the PR ready, then moves the items"); c0730 Design ("`cmd.done` … each moved item's `check.sh` is rewritten"), c0730 and c0760 Regression guard.
Evidence: c0730 changes what `done` does, so an executor updating the docs will naturally reword the `done` row and Phase 5 step 3 (for example "then moves the items to `done/`, rewriting their check.sh paths"). If a rewording drops one of those exact phrases, c0070's AC3 goes red. No RC runs c0070's check.sh, and the Regression guard's "Wording pinned" list doesn't mention it.
Recommendation: add to c0730's "Wording pinned by promoted specs" list: c0070 `check.sh` AC3 needs "marks the PR **ready** before its final push" and "the push starts the `pull_request` run" in the tracker skill, and "marks the PR ready, then moves the items" in execute-raft. Optionally add `tracker/issues/done/c0070/check.sh` to RC5's list. Its specs are short, and it passes on `main` today.

### F3 [low] Small mismatches between the documents and the specs or code order
Where and evidence:
- **c0730 Design step 2** says a dirty main checkout must "fail naming the problem", and c0740 inherits "the same guards". But ready.spec:283 requires the word `clean` in stderr. A message like "the main checkout has uncommitted changes" is correct by the document and fails the spec.
- **c0760, "Callers"** says ready and stop pull the main checkout themselves, so "the refresh's fast-forward is then a no-op". With `published()` wrapping `publish.commit`, the refresh runs inside the publish, before `ready`'s or `stop`'s own pull and before `stop` deletes `prompt.md` (c0740 step 3). The result is still right, because the refresh's `sweepStale(root)` removes the left-behind `active/<R>` with its prompt. But the stated order is reversed, and `stop`'s own delete becomes a no-op.
- **c0730's USAGE section** moves the `prompt` line to c0750. But c0730's AC10 (`grep -rnIi clipboard … scripts`) fails while USAGE still reads "render the execution prompt to the clipboard" (main.luau:35). c0730 has to change that line itself, before c0750, and its design doesn't say so.

Recommendation:
- Write the refusal text into c0730 step 2: `the main checkout is not clean (git status --porcelain)`, and `the main checkout is on <branch>, not main`.
- Correct c0760's sentence: the refresh runs first, and `ready`'s and `stop`'s own pull and delete then find nothing left to do.
- In c0730's USAGE bullet, say that the interim `prompt <id> --stdout` line drops "to the clipboard".

Verdict: changes
