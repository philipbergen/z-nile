# Review 005: c0247 (design mode)
Inputs: worktree `prep-ticket-confirms-intent` at 338d986d plus its staged `c0247.md`, `check.sh`, `acceptance/docs.spec.luau`, rounds 001 to 004 and their refutes, `harvest.md` and the three new lessons. A scratch clone under `$TMPDIR/rv247r5`: today's origin/main 05ad98ba (only spend commits since round 4's 5dd869b3), then the prep's staged diff (committed as `prep`), then `proto247.patch` (both applied cleanly). Also `./zn capture c0247` (53ad228c, no marker), and on origin/main `z-nile/engine/dispatch.luau` (the prompt, lines 116-160; `next`, lines 283-292), z-ticket's `SKILL.md`, and c0135, c0181, c0250 and c0256.
Dropped from review-004: F2 (fixed: the paragraph names no file, so c0250 needs neither an Override nor an order), F3 (fixed: E5, the deferred-tool clause, M32), F4 (fixed: "leave its plan alone", M33), F5 (fixed, apart from the record in F2 below).

Round 4's fixes, re-run:
- **The prototype on today's main.** `./zn check c0247` in the clone: **8/8** in 3 min 38 s. The heredoc's line, the Design's quoted paragraph and the prototype's line are byte-identical, 1866 bytes and all ASCII.
- **AC2's order and adjacency.** The mutation runner (`scratchpad/r5/run.sh`, `mut.py`, `ac8.sh`, run through `./zn run`) confirms these. A zero-width space in "Otherwise" fails AC2. A trailing space after the `Next:` line's closing backtick fails AC2 and AC8.
- **AC8's line test.** It kills every mutant inside the line: a trailing space, CR, a curly apostrophe, NBSP, a tab, ZWSP, a `> ` quote, an indent, the paragraph split into two lines, two blank lines, and a second paragraph between this one and step 0.
- **The exact duplicate.** A copy of the paragraph after step 6 passes AC8 but fails AC4 (the count is 2).
- **`export PARA` reaches the `bash -c` child.** The trailing-space control fails with "the Confirm intent paragraph is not the Design's text", so PARA is not empty.
- **`awk -v`.** It would process backslash escapes, but the paragraph has none.
- **The c0120 path scanners** (focus 2). `check-paths.spec` and `finished.spec` on the clone: 10 passed, 0 failed. So the heredoc's `./zn new`, `./zn list backlog` and `./zn dispatch` words aren't taken as paths.
- **Later rewordings** (focus 2). The heredoc holds no item path, so z-ready's and `done`'s path rewrites leave it alone. A sequestered check.sh runs only at `./zn check` and `done`, and no gate reruns a finished one (zz-test, "Must run after promotion" only requires that it *can* run). So a later issue that rewords the paragraph changes c0247's promoted `docs.spec` through an Override, and AC8 never stands in its way.
- **The "dispatcher's prompt" wording** (focus 3) is runnable. `dispatch.prompt` tells every dispatched CLI: "Nobody will answer a question. When a decision needs the user …, write `{stateDir}/questions.md`, one `## Q<n>` heading per question with the options and what each costs, and stop." That is "the way the dispatcher's prompt tells you to ask the user a question". z-ticket's own Headless section says the same. `dispatch.next` stops on `f.questions` with "needs the user: answer questions.md, then ./zn dispatch retry <id>". The re-run's receipt of the answer is c0256's, and c0247 depends on it. Nothing in the prompt contradicts the paragraph.
- **Scope.** The title, the Problem, the three Solution bullets and the two `Decided with the user` lines are carried. Every captured outcome has a Design and a Checked criterion. No narrowing.

### F1 [high] AC8's placement test skips any non-blank line between the paragraph and step 0, and checks nothing above the paragraph, so round 4's "exempt" mutant passes again when written on its own line, which Markdown joins into the same paragraph
Where: `check.sh` `paragraph_exact` (the awk program and its comment "it is the line right before step 0 (one blank line between)"), AC8's label "sits right before step 0", Rules and mutants row M29 to M31 and M35
Evidence: in the clone, each mutant below kept the prototype otherwise unchanged. Each passed **AC8 = PASS** and **docs.spec 5 passed, 0 failed**:
- **next_line_exempt.** The line "A one-line request is clear enough and is filed at once." is inserted right after the paragraph line, with no blank line between them. The awk program sets `f=1` on the paragraph line. The next line isn't blank, so no rule fires and it's skipped. The blank line then sets `f=2`, and step 0 exits 0. Rendered, or read by an agent as Markdown, the exemption is the paragraph's last sentence. That is round 4's "exempt" mutant (M35), which AC8 was added to kill.
- **prev_line_exempt.** The line "For chores and one-line requests, skip what follows and file at once." is inserted right before the paragraph line. Nothing checks the lines above the paragraph.
- **comment_wrap.** `<!--` goes on the line before the paragraph and `-->` on the line after. The rule is commented out and still passes.
- **step0_tail_exempt.** Step 0 becomes "…before anything is created: (a one-line request needs no confirmation: go straight on) `cd …`". AC4 pins step 0 only up to "created:", and AC6 pins only its bold label.

Critique:
- This is the third round in a row to find a hole in this mechanism, which is pins of pieces plus a walk over the neighbouring lines. Round 3 found the order of two sentences, round 4 the order of three plus additions inside the line, and now the lines around the line.
- The unit an agent reads is the Markdown block, which runs from one blank line to the next, and the step it gates. A check of one physical line can't pin that block.
- The tempting fix is to make the awk program demand that the very next line is blank. That leaves prev_line_exempt, comment_wrap and step0_tail_exempt.

Consequences:
- Pinning the whole region from the end of the frontmatter through step 0's line also pins step 0's text after the new phrase. Main could edit that text before execution.
- So take step 0 from the merge base, as AC6 does (lesson `z-design/exact-checks-compare-against-the-merge-base`), with the one phrase substituted. Refuse, with a message, when the base's step 0 no longer contains ", before anything is created:", because the Design's edit no longer applies there.
- No in-flight issue edits that region. c0135 (R0061) edits step 2 and c0181 (R0074) step 6. No spec on origin/main pins step 0's text (`git grep -nE 'capture worktree|Open a capture|before anything is created' origin/main -- '*.luau' '*.sh'` finds no z-ticket pin).
- A contradiction written elsewhere in the file survives this check: an unbolded copy after step 6, or "create it before the confirmation if the user is away" added to step 2. My runs of both passed old and new AC8. A whole-file check against the merge base would catch them, but it turns red whenever a raft mate edits z-ticket, as c0250 may edit the Headless section (lesson `zz-test/no-change-claims-check-behaviour-not-the-raft-diff`). So record that residual as a `reasoned` row, left to code review.

Recommendation: in `check.sh`, replace `paragraph_exact` with a block check:
- Compute `want = "\n# Make an issue\n\n" PARA "\n\n" step0`.
- `step0` is the merge base's `^0\. ` line with ", before anything is created:" replaced by ", after the confirmation above and before anything is created:". Refuse when the base line lacks that phrase.
- `got` is the file's lines from the one after the frontmatter's closing `---` through the first `^0\. ` line.
- Compare `want` and `got` with `[[ == ]]`, and print a diff on a mismatch.
- I prototyped this as `scratchpad/r5/ac8b.sh`. It passes the control and kills next_line_exempt, prev_line_exempt, comment_wrap, step0_tail_exempt, para_after_para, two_blanks and trail_space.

The rest of the fix:
- Relabel AC8 (doc and `check.sh`): "the text from the title through step 0 is byte for byte the Design's (the paragraph, and step 0 as the merge base's with the phrase added)". Fix the false comment.
- Add rows M36 to M39 (the line after, the line before, a comment wrapper, step 0's tail), run them, and record the outcomes in E1.
- Add a `reasoned` row: "a contradiction elsewhere in the file (step 2, Headless, an unbolded copy): not checked, because a whole-file pin turns red on a raft mate's z-ticket edit; the code review judges it."
- Amend `z-design/most-specific-environment-first`'s How to apply: "pin the paragraph's block, from the blank line before it to the step it gates, not its line: Markdown joins adjacent lines".
Lesson: zz-test/narrowing-pins-the-whole-file

### F2 [low] The record lags the design: E1 and step 3 say 7/7, E1 records mutants only up to M22, and the Design says the paragraph is pinned only by the spec
Where: E1; Implementation steps 3; Design, "**The paragraph** (pinned sentence by sentence by `acceptance/docs.spec.luau`)"; Rules and mutants (M23 to M35 marked `run`)
Evidence:
- `./zn check c0247` prints `8/8 criteria passed`, but E1 and step 3 say "7/7".
- E1 says "the mutants M1 to M22 one at a time (rounds 1 and 2)". Thirteen rows (M23 to M35) are marked `run`, but no outcome is recorded for them. Round 4's Recommendation asked for "run them, and record the results in E1", and the refute answered "fixed".
- The paragraph is now also pinned by AC8, which the Design's heading doesn't say.
Recommendation:
- Change "7/7" to "8/8" in E1 and step 3.
- Extend E1 with the round 3 to 5 mutants (M23 to M39) and the AC each one fails.
- Say "pinned sentence by sentence by `acceptance/docs.spec.luau`, and as a block by check.sh AC8".
Lesson: z-design/prove-specs-pass-on-a-prototype

### F3 [low] E2 leaves what plan mode's approve choices do to OC1, but OC1 never approves
Where: E2 ("What the approve choices do (permission mode, context clearing) was not observed: they stay OC1"); OC1
Evidence: OC1 observes plan mode opening, that nothing is created before approval, and that a correction gives a new restatement. It never approves, so no step shows how each approve choice ends.
- Under "clear context", does the fresh context, which holds only the plan ending in `Next: capture with the z-ticket skill, steps 0 to 6; build nothing.`, count the plan as "already approved … in this conversation"? Or does it restate again?
- Does a plain approve leave the session in an edit-accepting permission mode?
Recommendation: add to OC1: "approve once with each choice the harness offers (including clearing the context where it is offered): the capture runs steps 0 to 6 without a second restatement, builds nothing else, and lands one issue; note the permission mode afterwards". If a choice restates again, that is a defect for a new issue.

Lessons pass (`./zn lessons --when design`):
- `zz-test/narrowing-pins-the-whole-file` ("can joining two lines … change what the pinned file asserts"): F1. Markdown's line joining is that defect.
- `z-design/spec-design-correspondence` ("does every check's label say exactly what its command verifies"): F1. The label says "right before step 0", which the awk program doesn't verify.
- `z-design/exact-checks-compare-against-the-merge-base`: shapes F1's step 0 source.
- `z-design/prove-specs-pass-on-a-prototype` ("does every later step that says that gate passes match the result that run recorded"): F2.
- `z-design/quote-other-preps-before-promising`: c0135, c0181, c0250 and c0256 were re-read on origin/main, and none touches the block.

Harvest:
- `z-design/most-specific-environment-first` is a real lesson. Its How to apply needs F1's block wording.
- `declaration-checks-use-the-exact-key` and `no-change-claims-check-behaviour-not-the-raft-diff` are general, not restated findings.

Candidate lesson (for the lead, zz-test): an exact-text pin of Markdown pins the block, from blank line to blank line, plus its neighbours, never a physical line, because adjacent lines render as one paragraph and a comment wrapper hides it. Check: does a sentence on the next line with no blank between, or `<!-- … -->` around the block, still pass?

Verdict: changes
