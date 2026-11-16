# Review 001: R0065 (design mode, raft)
Inputs: 03a97e18 (raft-pickman-chores); R0065.md, rafts/R0065/check.sh; c0155, c0159, c0164, c0170 documents, check.sh files and Touched/Overrides lines; `./zn workstreams R0065`; `./zn find` of every member, dependency and dependent; origin/R0056-white-ghost-green-walls and origin/R0059-frame-roundtrip-tolerance diffs; PRs #143 and #159 (both open).
Grouped: [c0155@2ec413b4f9c4, c0159@fda9c71123c2, c0164@f5503fb51712, c0170@4e8fe6f3ac76]

Checked and holding: no Touched path is shared (the four Touched lists are disjoint); `./zn workstreams` gives one parallel wave, as the Order says, and nothing relies on a member order. c0170's `tiers.violations` judges only `tests/unit/` and `tests/helper/` specs, and no member, nor R0053, R0056 or R0059, adds a `tests/unit` spec except R0059's `plain.spec`, which c0170 moves (R0056's branch adds only `tests/place/main-walls.spec.luau`). The recorded base blobs match today's tree: d0105 f8275618, f0033 fb1f21f2, f0102 7ed53cf0, c0106 1cc3ac44 (on HEAD), f0126's sequestered `views.spec` 5a57a554, and R0056's `main-walls.spec` 38b8f1cc; f0110's and f0146's specs are unchanged since 0db4aa6d. No dependency raft overrides a member's pinned files (f0109 Overrides: none; f0126 names f0104 and f0101 only; c0153 names f0013, f0018, f0030, f0032). Dependency states are as stated: f0110 and f0146 done; f0126 prepared in R0053; f0109 in active R0056 (PR #143); c0153 in active R0059 (PR #159). f0158 `depends_on` [f0109, c0159, f0110, f0126] and c0182 [f0110, f0126, f0143, f0158, c0155], as the Order quotes. The exit criteria list the right ACs.

### F1 [low] "costs the features after them nothing" holds only if R0059 lands before R0053
Where: R0065.md, Order & dependencies ("Grouping c0155 and c0159 with c0164 delays them only until f0126 is done, which costs the features after them nothing")
Evidence: the raft also waits for c0153 (R0059, via c0170), which neither f0158 nor c0182 depends on. R0053 cannot finish before R0056 (f0126 depends on f0109), so R0056 is covered, but R0059 is independent: if PR #159 is still open when f0126 is done, f0158 and c0182 wait on R0059 because c0170 sits in their prerequisite raft. The sentence names only c0164 as the delayer.
Critique: the claim is stated unconditionally, and the fallback (`unfold c0155 c0159`) does not mention c0170 as the other source of delay.
Consequences: none beyond the wording; unfolding c0170 instead would leave c0155, c0159 and c0164 bound only by f0126 and f0109.
Recommendation: say the delay is nil only while R0059 lands no later than R0053, and add to the fallback: if R0059 lags when R0053 is done, `./zn unfold R0065 c0170` (and raft it apart) rather than unfolding c0155 and c0159.

### F2 [low] Exit criteria imply c0170's meta case checks the other members' specs, and leave out the z-nile gate c0170 needs
Where: R0065.md, Exit criteria ("the full gate already runs c0170's meta case over the other members' promoted specs")
Evidence: `tiers.violations` judges only `tests/unit/` and `tests/helper/` specs (c0170 Design), so over the other members' `tests/acceptance/` specs it judges nothing; the Whole-raft design itself says so. Separately, c0170 edits `z-nile/skills/zz-test/SKILL.md` (it forces z-nile's full run, c0170 Affected specs), while RC0 is `--project pickman` only; check.sh's header leaves z-nile to the merger's `z-nile/check.sh --full`, which the Exit criteria do not mention.
Critique: a reader takes the sentence as a cross-member check that doesn't exist, and may skip the z-nile gate for a raft that changes a z-nile skill.
Consequences: none: no new RC is needed (c0170's E5 ran both gates green).
Recommendation: reword to "the members share no surface: c0170's rule judges no file another member adds"; add that c0170's zz-test edit is proven by z-nile's full gate at the merge (`z-nile/check.sh --full`), not by RC0.

Verdict: approve
