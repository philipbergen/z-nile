# Review 011: c0248 (design mode)
Inputs: prep worktree prep-c0248-r3 on 64439a438, working tree (round 010's answers, `git diff origin/main -- z-nile/.tracker/issues/c0248`): design-refute-010.md; c0248.md (outcome 4 "Stopped and readied again", E14, the Rules and mutants rows at lines 410 and 411, the Test plan's AC8 line, AC8's criterion, the Public surface, the f0399 Interfaces bullet, Implementation step 8); guesses.md G9; harvest.md's round-010 entries; check.sh's AC8 line; acceptance/layers-land.spec.luau (setup, R0100's seed, the AC8 kept assertion, the R0040 case); experiments/mutate.py; experiments/prototype.patch; z-nile/skills/z-design/lessons/identify-commits-by-what-they-are.md. Prototype proto-c0248-r3 @ ce2f3e130 (`git diff 7e49f8652 ce2f3e130`; main.luau `f0399.readyOnMembers` and `cmd.ready` up to its call; layergit.luau `landed`, `aboveLandingBase`; stack.luau `rebaseUpstream`). The prep's check.sh, layers-land.spec.luau, docs.spec.luau and mutate.py are byte-identical to the prototype's. The patch below its three header lines is byte-identical to `git diff 731152892 ce2f3e130 -- . ':!z-nile/.tracker' ':!pickman/.tracker'`. The recorded runs (layers-land 18 of 18; the three new mutants killed) are taken as given. I did not rerun them.

Scope: the four answers of design-refute-010.md and what they touched. Round 010's approvals and the settled design are not reopened.

What holds:
- F1 (the still-being-built variant). Layer 3 (c0105) is started on layer 2 after layer 2's restack in the first half. Layer 2 is then fixed, re-finished onto `M1` (its own fork, since its `c0100: ` row's parent is on main), reviewed and landed. Layer 3's range from its fork `M1` is `F2'`, layer 2's review and final-review commits, `tracker: start R0040`, `c0105 work`. `rebaseUpstream`'s rows are oldest first (`--reverse`). The first matching row is the start commit, whose parent is not on main, so `aboveLandingBase` returns main's tip and `finish c0105` refuses with HEAD unchanged. The helper `work` commits as `c0105 work`, not `c0105: `. So `above-landing-no-start-row` finds no row, falls back to the fork, and `finish c0105` succeeds: it is killed by this variant alone, as the lesson spec-design-correspondence asks. The finished variant's rows give it `F2`'s parent, which is off main. `above-landing-finished-only` (the newest row only) gets nil at the finished variant's review-commit tip and dies there. The row records this honestly. The `--through c0100` added to the first half's `trace` and `done` keeps the layer check as the refusal. The hand-written `final-review-002.md` is reused by `sealBind`, because `topLocal` 2 is greater than `top` 1 on main. The check.sh label, the Test plan line and the spec name agree word for word.
- F2. E14's sentence now names `731152892` and the exclusions the patch header uses, and the patch matches that diff at ce2f3e130, the main.luau hunk included.
- F3. The refusal runs after the fetch, so `layergit.landed` reads a fresh `origin/main`. It runs before the walk and before anything is published (`cmd.ready` calls `readyOnMembers` ahead of the claim). The AC8 kept assertion runs in the fixture's `f.main` on R0100. R0100 is seeded prepared and never readied, and its member depends on c0030, which is not landed. The assertion pins the new words and the absence of "is not finished". The mutant `ready-on-partly-landed` restores the walk's wrong words, so the assertion kills it. The outcome 4 sentence quotes the message exactly. The setup case's "nine readied rafts" is still true.
- F4. G9 is dated 2026-11-20. The harvest entries name existing lessons (identify-commits-by-what-they-are, every-state-a-placed-command-meets), and the note added to identify-commits-by-what-they-are states the round's lesson in its own check line.

### F1 [low] The `--on` refusal's way out waits for D's last layer even when everything R depends on in D has already landed
Where: c0248.md outcome 4, "Stopped and readied again" (the quoted message); prototype `f0399.readyOnMembers` (main.luau around line 6985).
Evidence: `any` is set for every dependency in `inBase`, landed or not. Take a raft R whose members depend only on c0010, and suppose c0010 has landed with `done D --through c0010`. Then `ready R --on D` refuses with "ready R without --on once D's last layer lands (./zn done D)". But c0010 is in `done/` on `origin/main`, so `ready R` without `--on` already passes the dependency check now.
Critique: The message gives a way out that works, but it is not the earliest one. It sends the person to wait for layers that R does not need.
Consequences: none
Recommendation: Word the way out by what R depends on: "ready <R> without --on once the members of <D> it depends on have landed (./zn done <D> --through <id>)". Or name both cases. Change outcome 4's quote and the case's literal only if the asserted prefix changes. It does not: the case reads only "--on R0010: R0010 is partly landed (c0010, c0020)".
Erred: z-design
Upstream: none

### F2 [low] The new `--on` refusal is stated only in outcome 4 and its Rules row, not where the f0399 interface and main.luau's changes are listed
Where: c0248.md, the f0399 Interfaces bullet (line 182), the Public surface's `z-nile/engine/main.luau` line (line 244), and Implementation step 8.
Evidence: The f0399 bullet still lists only `raftBase` and `done`'s refusal. The main.luau line lists "`ready`'s marker and its skip of landed members". Step 8 lists "`ready` after it". None of them says that c0248 adds a refusal to f0399's `ready --on`.
Critique: This changes another issue's rule, f0399's `--on`, and an executor working from the steps can miss it until AC8 kept fails (lesson restated-rules-move-together).
Consequences: none
Recommendation: Add "`ready --on` refuses a partly landed base raft (outcome 4)" to the f0399 bullet, the main.luau line and step 8.
Erred: z-design
Upstream: none

Verdict: approve
