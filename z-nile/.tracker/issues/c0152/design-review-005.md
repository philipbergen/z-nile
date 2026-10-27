# Review 005: c0152 (design mode)
Inputs: prep `prep-merge-past-tracker-only` 04caaf35 (`git diff 5a0aa1f7 04caaf35`: c0152.md, design-refute-004.md, the docs and merge-check specs, harvest.md, the zz-arch and zz-test lessons); prototype `proto-merge-past-tracker-only` bb94742a (`git diff b428a7c5 bb94742a`: `liveItem` in `mergecheck.judge`, zz-rules step 4 and the row). Everything ran in a scratchpad `--no-hardlinks` clone of the repository with origin removed (`r5`): bb94742a merged with today's origin/main 70a84744 (clean), and the three acceptance specs copied to `z-nile/tests/acceptance/c0152/`. Mutants ran in a second clone of that one (`r6`). Lune 0.10.5. Load averages were 100–130 throughout (18 cores).
Dropped from design-review-004: F1, F2, F3

Rulings on refute 004 (each re-run, not read):
- F1 fixed. The full merge-check.spec passes 14/14 on bb94742a plus today's main (54 min 51 s wall at load ~110; 110 s user and 357 s sys CPU). I ran a reduced copy with setup, the two bound cases and the cleanup case, with `MAX_TRIALS = 2`: 2 passed, 2 failed (both bound cases). With `MAX_TRIALS = 4`: 2 passed, 2 failed (both bound cases). Both are killed. Rule 3, AC1, the Rules row and zz-rules all state the outcomes after the third trial, and the zz-rules instruction for "kept moving" is now one instruction.
- F2 fixed for the PR's side. The case "a first spend row at the old folder of an item the PR moves" passes in the full run. One half of the new rule still has no case (F1 below).
- F3 fixed. docs.spec and stages.spec pass (5/5) on the merged tree. The zz-rules wording ("run it in the background (or with no timeout)") is pinned.
- I re-checked rule 3's loop in `judge` against the design text: the cap, the fourth tip read, `tip = now` before the notrial break, and the "kept moving" no. All agree.

### F1 [medium] The "else main's" half of the live-item rule has no case: a mutant that always reads the PR's copy passes every spec and gives ok over a main whose own commits orphaned a spend row
Where: Design rule 3 ("the PR's copy when the PR changed that folder, else main's"); prototype `liveItem` (`{if prChanged then h else at}:{folder}/{id}.md`); the Rules row "a notrial row counts only for a live item" (only Y4)
Evidence: the sequestered cases that reach `liveItem` are c0902's spend rows (c0902 is in both the PR's head and main, so both copies say live) and the F2 case (the PR changed c0901's folder, so `h` is read either way). Neither tells `h` apart from `now` when the PR didn't touch the folder. I ran it. Mutant: `{h}:{folder}/{id}.md` always. Case (in `r6`, a reduced copy: setup, this case, the cleanup case): during trial 1 the probe pushes `tracker: done c0902` (c0902 moved to `done/`, which is tracker state but not notrial, so a second trial runs). During trial 2 it pushes `tracker: spend c0902 (old folder)`, a new `issues/c0902/spend.md`.
- Prototype as is: 3 passed, 0 failed. `now` has no `c0902/c0902.md`, so the row isn't live and trial 3 runs. classified then fails with "duplicate id c0902: z-nile/.tracker/issues/c0902, z-nile/.tracker/issues/done/c0902", and the verdict is no.
- The mutant: 2 passed, 1 failed. Its output is "origin's main moved during the check by 1 commit(s) changing only files the stage list marks notrial: not tried again … judged main 25184e2b…", exit 0. That is an ok over a main whose merged tree fails classified and audit.
Critique: this is the same mechanism as round 004 F2, with a stale-path spend row, but written by main's own side. A `./zn spend` from a session that hasn't seen a `done` lands exactly this. Main is then red whatever the PR does, but merge-check promised that the merged tree passes every stage, and the mutant answers ok without running one. The obvious fix is the case above. Consequences: none beyond the case. The prototype already behaves right, so this only pins it.
Recommendation: add the case "main moves an item the PR doesn't touch, then a spend row at its old folder: never ok" to merge-check.spec. Expect exit 1 and no `judged main`, and accept either the classified or the audit failure, as the F2 case does. Add mutant Y5 "the PR's copy always (`h`)" to the live-item row, plus Y6 "main's copy always", which the existing F2 case already kills. Record both outcomes in E6.
Lesson: zz-test/pin-call-site-arguments (both values of the copy that `liveItem` reads)

### F2 [medium] The merge-check spec has never run on Linux CI, and its stated cost is stale
Where: Scalability ("The fixture spec takes about a minute at low load and 11 minutes at load 52"); E6 (1381 s "at a load of about 14"); `.github/workflows/check.yml` (`z-nile/check.sh --project "$PROJECT" --full` on `ubuntu-latest`)
Evidence:
- The design records no Linux run. `grep -n -i 'linux\|ci-verify' c0152.md` finds only E5's residual-risk note.
- The lesson's check asks: "has each platform the specs run on (macOS in the jail, Linux in CI, which `z-nile/ci-verify.sh` reaches from a throwaway branch) run them on the prototype". That line has been in the lesson since 34950af3 (2026-10-25 07:39), before this issue was captured.
- Once promoted, the spec runs in every PR's z-nile CI gate. It runs nested `tests/run` stages in trials under `.cache` on a host with no jail (`PICKMAN_TEST_JAIL` none on Linux), and the F2 case accepts either git's rename conflict or an audit failure, which can depend on the git version.
- Its cost has grown with each round: "about a minute" (round 002) became 1381 s (E6, about 16 trials). My run took 3291 s wall at load ~110, with 467 s of CPU.
- Today the z-nile job takes about 11 minutes (`gh run view 40423000070`: gate (z-nile) 23:55:22 to 00:06:18). Nobody knows whether this one spec becomes that job's critical path. If it does, every PR's cycle gets longer, which is the cycle the issue exists to shorten.
Critique: an executor who finds it red or slow on CI can't edit the sequestered spec, and z-design requires proof on every platform the specs run on.
Recommendation:
- In prep, put the prototype with the three specs at their promoted path on a throwaway branch, run `z-nile/ci-verify.sh`, and record the result and the spec's time in the z-nile job next to the job's total.
- Correct the Scalability sentence with measured figures.
- If the spec stretches the job beyond its current wall time, shrink its cost without dropping a case: seed only the files the four stages and the engine read, not the whole working tree, and say so in the Test plan.
Lesson: z-design/prove-specs-pass-on-a-prototype

### F3 [low] Scalability's re-trial rates assume a 180-s check; the design's own figure under load is 600 s or more
Where: Scalability ("for 180 s … about 10% of checks run a second trial, and fewer than 1% a third"); rule text "10 or more under load"
Evidence: the same method, run on main's first-parent log since 2026-10-25 08:00 (266 commits). The window is placed every 30 s. A commit is "spend" when its subject starts `tracker: spend`, and a "PR merge" when the subject has `(#`:
```
git log --first-parent --format='%ct|%s' --since='2026-10-25 08:00' origin/main
180  moved 23%  spend-only 12%  retrial-needed 11%  with a PR merge 3%
600  moved 44%  spend-only 17%  retrial-needed 27%  with a PR merge 10%
1200 moved 52%  spend-only 15%  retrial-needed 38%  with a PR merge 16%
```
So under load about 27–38% of checks run a second trial, roughly 7–14% a third, and 10–16% end in a no because a prep or raft PR merged meanwhile. That still converges, below round 003's threshold of half, so there is no escalation. But the stated rate is three times too low for the condition the design says is usual.
Recommendation: state the 600-s and 1200-s rows beside the 180-s row, with the command, in Scalability.

Candidate lesson (for the lead):
- zz-test: a rule that picks between two sources ("the PR's copy when X, else main's") needs a case where the two sources disagree in each branch; cases where both agree pass whichever one is read. Check: for each "A when X, else B" in the design, is there a case with X false where A and B differ?

No high findings: nothing goes to the user from this round.

Verdict: changes
