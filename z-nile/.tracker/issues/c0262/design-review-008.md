# Review 008: c0262 (design mode)
Inputs: prep worktree `prep-c0262-r2` at 72a282566 with its working tree (`c0262.md`: Rules and mutants, the Mutation check paragraph, criterion AC8; `check.sh`; `acceptance/docs.spec.luau`; `design-refute-007.md`; `z-nile/skills/z-design/lessons/restated-rules-move-together.md`); `design-review-007.md`; prototype `proto-c0262-r3` = `origin/proto-c0262-r3` = 99209a6fb (`git diff ae32160c1 99209a6fb`: docs.spec gains one pin, AC8's `check.sh` label gains "each resolve decision's next step is said"). Checked: the prep's `check.sh` and all seven `acceptance/*.spec.luau` are byte-identical (`cmp`) to 99209a6fb's, and 99209a6fb has no other acceptance file. Runs on `proto-c0262-r2-mut` (at 99209a6fb, clean, restored after; `git status` empty): docs.spec 4/4; mutant M75 (" (unless no member is left to land)" dropped from zz-execute 4a) fails docs.spec AC12 at docs.spec:67 on an assertion (3/4).

What holds: round 6 F1. docs.spec AC12 now pins "and the raft is readied again without it (unless no member is left to land)", which is the sentence in zz-execute 4a word for word, and M75 dies (run above). The table has rows for "after a split the worker captures nothing" (M73, work.spec AC8 and docs.spec AC12, run) and "the redo-design why names the ruling it came from" (M74, verdict.spec AC14, run), and the M72 row carries M75. Both rows' mutants died in round 6's runs. Criterion AC8 now ends with each resolve decision's next step, and the `check.sh` label follows it. Round 6 F2. The lesson's `check:` ends with the who-acts question, and its body records this prep's case. The prototype's change since round 6 adds one assertion and changes one label string, and brings no defect.

### F1 [low] The Mutation check paragraph's count says 42 for a list of 41
Where: c0262.md, Unknowns & experiments, Mutation check paragraph ("M33, M36 to M53, M55 to M66, M61b, M68, M68f and M69 to M75, 42 mutants"); design-refute-007.md F1 ("the mutation summary counts 42").
Evidence: the list has M33 (1), M36 to M53 (18), M55 to M66 (12), M61b, M68 and M68f (3) and M69 to M75 (7): 41. The table's `run` rows (not "earlier prototype") name exactly those 41 ids and no others; M54 is `reasoned` and M67 does not exist.
Critique: the count is a restatement of the list, and a later reviewer or the gate's reader takes it as the number of mutants that were run. The easy fix is to change the number and leave it there, when the next added row will drift it again.
Consequences: none beyond the one number.
Recommendation: change "42 mutants" to "41 mutants". When a row is added later, recount from the list rather than adding to the old total.
Lesson: z-design/restated-rules-move-together
Erred: z-design
Upstream: none

Lesson candidate: none new.

Verdict: approve
