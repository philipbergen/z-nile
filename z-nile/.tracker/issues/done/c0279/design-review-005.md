# Review 005: c0279 (design mode)
Inputs: prep `prep-dispatch-stop-spec` at 4324a19c (c0279.md, check.sh, acceptance/pins.sh, acceptance/fakecli-modes.expected, acceptance/dispatch-cli.spec.expected.diff, experiments/*.txt, harvest.md, spend.md, design-review-001..004 and design-refute-001..004, the lesson edits against origin/main); prototype `proto-c0279` at 0014dbe8 (`git diff 1808a041 proto-c0279`, `git diff 3cebeda3 0014dbe8`); the author's last run script `last.sh` and raw outputs (`mute-M11-tool-limit-ignored.txt`, `mute-final-plain.txt`, `mute-final-delay.txt`, `others-final.txt`, `mut4.sh`, `loop4.sh`) in the session scratchpad, and the author's transcript's timestamps for the commands that produced them; z-nile/engine/runner.luau (the run loop, lines 150-290); tests/lib/fakecli.luau; tests/tooling/repo-fence.spec.luau (NAMES, ALLOWED); `./zn capture c0279` (e88f68b6, no marker); PR #274; `./zn lessons --skill zz-review`. Probes, all read-only on the repository and through `./zn run` where they ran a program: pins.sh on 0014dbe8 (exit 0) and on the unfixed base worktree (exit 1, 20 lines); a first-line probe on scratch copies of the prototype's two files (below); AC3's blob and golden diff recomputed; stylua and selene on the two prototype files (clean); `./zn promote-check c0279` (OK); `./zn lessons --check` and `--uncovered c0279` (ok); `git ls-remote origin main` (ae926c87: the spec's blob still 4fec0246, fakecli's still dbf15a32); `git merge-tree` of the prep branch with origin/main (F5). No spec run (the brief).
Dropped from design-review-004: F1 (the Rules row exists and M11 ran on 0014dbe8's files at FAKE_DELAY unset, killed by the tool case alone at spec:690; the unstated margin is repeated as F2 here), F2 (the first line is a builtin test, pinned exactly, and the three other users ran on 0014dbe8: 41 passed), F3 (c0194's lesson restored, check widened, c0279 added as an `**Also:**`), F4 (the claims are rewritten for the decision; the missed-stall margin it asked to name cannot be missed, see Checked), F6 (exact pin; my probe below kills three wrong first lines). F5 is partly repeated as F1 here, F7 as F4.

### F1 [low] Round 4's sweep left stale text that contradicts the check, and the refute says it was fixed (repeat of design-review-004 F5)
Where: c0279.md Design, Changes (d) (line 41); Implementation step 0 (line 117); E7 (line 73), E9 (line 75), E5 (line 71); check.sh, the AC2 comment (lines 13 and 14); acceptance/pins.sh line 43; design-refute-004 F5.
Evidence:
- Changes (d) still says "the script's first command after the shebang is `sleep ${FAKE_DELAY:-0}`". pins.sh now requires exactly `[[[ -z "${FAKE_DELAY:-}" ] || sleep "$FAKE_DELAY"]],`, and my probe shows that `"sleep ${FAKE_DELAY:-0}",` fails AC1 (`DIFFERS (every CLI fake)`). Step 1 allows the executor to "write them from the Design", which then fails AC1. Round 4 F2's Consequences named this edit ("and Changes (d)").
- Step 0 still re-preps only when main moves "`fakecli.luau`'s `stop`, `cap` or `push` modes". pins.sh also pins the `tool` entry and the first line after the shebang. c0287 (control-cli's orphan wait, captured on main) is the next item likely to edit fakecli.
- check.sh's AC2 comment still says only "the stop and the push wait 3 s". pins.sh's comment still says "the three entries", while its loop pins four.
- E7 is still headed "(final prototype)". E8 and E9 are headed that way too, so three different commits carry the name.
- E9 says "M11 as above", but no M11 text comes above it. M11's outcome is recorded only in the Rules row, and zz-review item 0 expects run rows to be recorded in Unknowns & experiments.
- E9 says that since the M1 to M4 runs "the commits since changed the first line of the CLI fake, the tool fake and c0040's limits only". For M1 to M4 (run on 13aca7c8's era) that is false: E7 itself lists the root limits, the 3600 s hold and grandchild, and the wall-clock bound. The conclusion still holds by reading, because each of those mutants dies the same way on 0014dbe8.
- E5 does not name c0287. Round 4 F2 asked for it there.
- design-refute-004 F5 says "fixed: steps, golden length (84), size 50, comments, E3/E4/E8 wording". The golden length, size, E3, E4, E8 and step 1 are fixed. Step 0, the comments and E7 are not.
Critique: this is the third round running whose answer left restated text behind (design-review-003 F3, design-review-004 F4 and F5). Each sweep was by hand, and the refute line reported it done. The executor is protected by the exact pins and by step 1's prototype diff, so this is not a wrong result. But the record no longer says what the check enforces, and a refute line that says `fixed` for unchanged lines makes the next reader distrust every answer.
Consequences: none for the design. The edits are prose. check.sh and pins.sh change in comments only, and AC1 and AC3 compare neither file.
Recommendation:
- Rewrite Changes (d) as the exact builtin line.
- In step 0, name the `tool` entry and the lines between the shebang and `case "$mode" in`.
- Fix the two comments, and give E7 and E8 their commit names instead of "final".
- Put M11's run (file, commit 0014dbe8, FAKE_DELAY unset, the one failure at spec:690) into E9, and correct E9's M1 to M4 sentence to point at E7.
- Name c0287 in E5.
- Question the mechanism: answer every bullet of a finding's Evidence by its own line in the refute (changed, or why not), from a grep you rerun after the edit (for example `grep -n 'sleep \${FAKE_DELAY:-0}\|three\|stop`, `cap` or `push`\|final prototype' c0279.md check.sh acceptance/pins.sh`).
Lesson: z-design/restated-rules-move-together

### F2 [low] The tool case's 2 s detection margin, and the option the refute says goes to the user, are not in the issue (repeat of design-review-004 F1)
Where: Rules and mutants, the M11 row; Changes (e); Scalability; design-refute-004 F1 ("the margin (12 s quiet over a 10 s stall limit) is stated and left to the user to lengthen").
Evidence:
- `grep -n "margin\|lengthen\|miss" c0279.md` finds one margin only, the false-stall one in "Why this holds" ("10 s of silence, 7 s under AC2's delay"). It finds no word on the tool case's 12 - 10 = 2 s, and no recorded option for the user.
- What the margin means, read from runner.luau: `quiet` resets when the `tool_use` chunk is read (line 162). Under M11 the step stalls 10 s after that read. The `tool_result` comes 12 s after the write. So a run in which the read lags the write by more than about 2 s does not see M11. It is never a false red: a correct runner uses the 30 s tool limit, 18 s clear.
Critique: the row reads as an unconditional kill, but under the load this issue was written for, a run can miss the regression it guards. Round 4 asked for the sentence, and the refute says it is there.
Consequences: none for the design. A longer quiet call (for example 20 s: 10 s each side, about +8 s per run) is the user's call, as round 4 said.
Recommendation: add one sentence to the M11 row or Changes (e): "the case sees M11 only when the `tool_use` line is read within about 2 s of its write. A loaded run can miss it, never turn red. A longer quiet call costs time per run and is the user's choice." Put that choice in the final report to the user, since this round is the last.

### F3 [low] The first-line rule ("spawns nothing when unset, delays every fake when set") has no Rules row
Where: Rules and mutants; Solution (`FAKE_DELAY` paragraph); pins.sh lines 24 to 27.
Evidence:
- Round 4's answer made this a behavioural rule of the fake: a builtin no-op when unset, before any output when set. Its only kill is AC1's exact pin.
- The "the fakes' exact text is the reviewed text" row lists only the stop fake's three wrong variants (`pins-wrong-fakes.txt`, run at 21:19, before the first-line pin existed).
- My probe ran pins.sh on scratch copies of 0014dbe8's two files, one variant each:
  - the old `"sleep ${FAKE_DELAY:-0}",`: rc 1;
  - the backgrounded `... || sleep "$FAKE_DELAY" &`: rc 1;
  - the line moved after the `step=` line: rc 1;
  - an extra comment line before it: rc 0, which is correct, since comments are skipped.
  Each failure printed the `DIFFERS (every CLI fake)` line. The rule holds. Only the row is missing.
Recommendation: add the row: "the CLI fake's first command is a builtin test that spawns nothing when `FAKE_DELAY` is unset and sleeps before any output when it is set" | AC1 pins.sh (exact first line), AC2 | `sleep ${FAKE_DELAY:-0}` (a process in every user's 3 s window), a backgrounded sleep, the line after the first output | `run`. Record those three variants in experiments/ (this probe, or the author's own rerun).
Lesson: z-design/spec-design-correspondence

### F4 [low] PR #274 still carries the pre-decision design, open and not a draft, though the refute says it was updated (repeat of design-review-004 F7)
Where: PR #274; design-refute-004 F7 ("PR #274 is updated with this commit").
Evidence:
- `gh pr view 274` gives head `da11f85f`, `isDraft: false`, `state: OPEN`. `git ls-remote origin prep-dispatch-stop-spec` gives `da11f85f`. The prep worktree's HEAD is 4324a19c, so neither 9877d342 nor 4324a19c is pushed.
- In da11f85f c0040 is at 2 s, and there is no Scope decision "Widen them to 10 s" and no M10 or M11. Yet it has `design: ready` and `status: prepared-walrus-sunny-lucky`.
- The standing "merge when green" practice means any session may merge a green PR. Merging this head would put a prepared design on main that contradicts the user's decision.
Recommendation: push the prep branch with this round's files now, or mark #274 draft until the coordinator's final report is read. Don't let `fixed`/`acknowledged` describe a push that has not happened.
Lesson: z-design/required-steps-on-every-path

### F5 [low] The prep branch conflicts with main in a lesson file; a careless resolution drops c0246's note
Where: z-nile/skills/z-design/lessons/spec-design-correspondence.md.
Evidence:
- `git merge-tree --write-tree --name-only HEAD origin/main` (merge base 671613d8) reports `CONFLICT (content)` in this file.
- Main's 1758cf21 (c0246's prep, #264) appended "Note (c0246 round 7): when a function's answer gains a value …" at the end. The prep appended "**Also:** c0279 design review 002 F3: …" at the same place.
- Read two-dot, `git diff origin/main -- z-nile/skills/` shows the prep "replacing" c0246's note. Taking the prep's side drops a lesson, which is the same loss as design-review-004 F3.
Recommendation: merge origin/main into the prep branch before pushing, keep both paragraphs (c0246's note, then c0279's `**Also:**`), and run `./zn lessons --check` after.

### F6 [low] Round 4's spend rows are not recorded (repeat of design-review-002 F7 / design-review-003 F5)
Where: spend.md (prep) and `origin/main:z-nile/.tracker/issues/c0279/spend.md`.
Evidence:
- The prep's spend.md ends at row 7 (design-refute-003). Main's ends at row 8 (prep).
- No row for design-review-004 (the reviewer's minutes and tokens) or design-refute-004 exists anywhere. Both are long finished.
- z-design 5.2 says "as soon as a subagent reviewer returns, whatever its verdict … `./zn spend <id> --phase design-review …`", and 5.3 adds the answering row.
Recommendation: record both rows now, and this round's when it returns. Then `./zn metrics` counts five rounds.

Checked without a finding:
- AC3, recomputed:
  - In the proto worktree, `git hash-object` and `git rev-parse proto-c0279:<spec>` both give `28d078baee03277c5a8f56e7d7d53995c538307e`, the blob in check.sh and AC3.
  - The diff from the merge base (1808a041), less its index line, equals acceptance/dispatch-cli.spec.expected.diff byte for byte, 84 lines.
  - Remote main ae926c87 still has spec blob 4fec0246 and fakecli blob dbf15a32. Since 1808a041, only c61cc96b (`tests/lib/cachepaths.luau`) touched tests/lib, c0117's specs or the engine.
- pins.sh:
  - Exit 0 on 0014dbe8.
  - Exit 1 on the unfixed base, with 20 MISSING, PRESENT or DIFFERS lines, among them the exact first-line pin and all four entries.
  - Its awk takes the first `"#!/bin/sh",` (line 39, the CLI fake), ahead of the two harness scripts at lines 162 and 191.
- The runs E6 and E9 cite ran on 0014dbe8. The author's transcript shows the proto commit at 06:34:25Z, `last.sh` started at 06:34:54Z and the other-specs run at 06:34:56Z. `last.sh` copies proto's fakecli and spec into the base worktree, and its mutation helper asserts the pattern occurs exactly once.
  - M11 (FAKE_DELAY unset): 24 passed, 1 failed, the tool case at spec:690.
  - Plain: 25 of 25.
  - FAKE_DELAY=3: 25 of 25, passed in with the same `env $2 ../zn run` mechanism that made M10 and M2 fail in round 4, so the delay reached the fakes.
  - Other specs: 41 passed in the proto worktree.
- The missed-stall side that design-review-004 F4 asked to name cannot be missed. In runner.luau's loop the stall test runs in the body after `quiet += dt`, with no yield between it and the `while` condition. The reader task breaks on EOF without resetting `quiet`. A starve that spans the `wait`, `prose` or `stall` fake's exit is therefore still charged and reported as `stalled` or quota. Only the false-stall side (10 s, 7 s under AC2) depends on load, and the Design names it.
- The first line is correct `sh`. `[` is a builtin in bash's POSIX mode and in dash. An empty or unset `FAKE_DELAY` runs no `sleep`, and `FAKE_DELAY=3` runs `sleep "3"`. The Luau long string `[[[ … "$FAKE_DELAY"]]` closes at the first `]]`, after the closing quote.
- deadWithin:
  - The killed grandchild is reparented when its parent (the fake, in the same group) dies, and is reaped by launchd. A zombie window falls inside the 60 s bound.
  - "No such process" is the C-locale `ESRCH` text for both macOS's and Linux's `kill`.
- Repository safety:
  - AC1 is greps, awk and sed. AC2 runs under the runner's jail. AC3 runs `git hash-object` without `-w`, plus a diff and a merge-base.
  - The acceptance files and check.sh name nothing in repo-fence's NAMES list, so they are safe to promote into tests/acceptance/c0279/.
  - The author's scripts ran through `./zn run --time` and restored the base worktree (`git checkout -q -- .`, clean now).
- size 50 = `git diff --numstat 1808a041 proto-c0279` (24+12, 10+4).
- stylua and selene are clean on both prototype files. `./zn promote-check c0279` is OK. `./zn lessons --check` and `--uncovered c0279` pass.
- Scope: the capture (e88f68b6) has only gained `Scope decision` lines. The third one carries the user's words and the option's text. Every captured outcome has a Design and a Checked criterion. c0287 holds control-cli by the user's scope, and no other open item touches fakecli or the spec (`git grep` on origin/main finds only c0247's review text, which runs the spec but does not edit it).
- Lessons since round 4:
  - `zz-test/shared-fake-knobs-spawn-nothing-when-unset` is a rule another raft could fail, not a restated finding.
  - The c0279 note on restated-rules-move-together generalises its finding.
  - read-back-every-prototype-edit keeps c0194's body, Why and How to apply. Its check widens to mutants and to patterns that occur more than once.

Lesson candidates (for the lead):
- z-design, a note on restated-rules-move-together (or a new lesson): a `fixed:` answer to a finding whose Evidence is a list must answer each bullet on its own line, because round 4's F5 listed ten stale places, four stayed, and the refute said "fixed". Check: for each bullet of the finding's Evidence, can the refute point to the changed line, or say why it stays?

Verdict: approve
