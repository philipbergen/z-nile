# Review NNN: R0094 (design mode)
Inputs: raft-d0298 at f91a8c33b671 (R0094.md last changed in 3ab49e2c); `pickman/.tracker/rafts/R0094/R0094.md` and `check.sh`; the members' documents, `check.sh` and `acceptance/` (f0143, f0147, f0158); `./zn workstreams R0094`; `./zn find` on every member's `depends_on` and on c0176, c0177, c0182, c0196, d0149, f0148; `pickman/.tracker/game-design.md`, `architecture.md`, `src/shared/Logic/Session/init.luau`, `src/client/Controls.luau` on this tree; the z-raft lessons.
Grouped: [f0143@9de19e99185d, f0147@deb99c51e2b8, f0158@59277d5ddbf9]

Checked and sound, so not raised: `./zn workstreams R0094` prints the Order as written. Every member `depends_on` outside the raft except c0176 and c0177 is in `done/`. Both of those are `new`, `design: draft`, with no raft, as the raft says. z-ready step 1 refuses on them. The speed line meets cleanly: `Session.speeds(s.config, member.play.level, frightened).player` is already the step's line on this tree (Session/init.luau:644). f0143 wraps it, f0147 changes only the function behind it, and f0147's levels.spec "the player runs the ramp's speed on each level: 21 units a step on level 1" pins the unboosted path. f0143's boost.spec pins the chevron inside the lives block, which f0158's clear.spec measures. No f0143 spec reads `GAME_CONFIG`. The architecture.md claims hold: f0147's Game, Ghosts, Session and Picks uses sit inside the existing `Game -> Levels`, `Ghosts -> Levels/Movement` and `Session -> Picks` edges, and f0158's `Awareness -> Maze` is unchanged.

### F1 [medium] Grouping makes f0143's and f0158's dependents wait on c0176 and c0177, which only f0147 needs, and the Order names neither the wait nor a fallback
Where: R0094.md, Order & dependencies ("After this raft: d0149 (R0066) `depends_on` f0143 and f0158; c0182 `depends_on` f0143 and f0158 …") and Risks ("c0176 and c0177 are unfinished … f0147's narrowed promoted specs fail").
Evidence: one raft is one branch and one PR, so f0143 and f0158 reach `done/` only when R0094 does. R0094 can't be readied until c0176 and c0177 are done. Both are drafts that have to be designed, rafted and executed first (`./zn find`: `new-toucan-violet-pink` and `new-quiet-badger-lucky`, `raft:` empty; c0177 also `depends_on: [f0125]`). d0149 (`depends_on: [d0151, f0110, f0143, f0126, f0158, c0182]`, prepared in R0066) and c0182 (`depends_on: [f0110, f0126, f0143, f0158, c0155]`) need neither chore. Grouped apart, f0143 and f0158 could land without waiting. Grouped here, they wait. The raft treats the c0176/c0177 wait as a risk to f0147's specs alone.
Critique: the cost of grouping falls on R0066's touch circles and on c0182, and nothing in the record says so. The fix the author will reach for is one more bullet under "After this raft". That bullet alone leaves the executor and the next rafter with no rule for when the chores lag.
Consequences: a stated fallback (unfold f0147 when the chores lag) adds a decision point. Unfolding f0147 changes R0094's record, but per z-raft §4 an unfold alone needs no new coherence review. f0147 out of R0094 would then sit beside R0095 (f0148 `depends_on: [f0147]`). f0147's Whole-raft facts (it builds on f0143's Hud and HudView additions) hold in either landing order, because its Regression guard and hud.spec's stub-loader fallback cover f0143 before or after.
Recommendation: in Order & dependencies, list each dependent's added wait: d0149/R0066 and c0182 now wait for c0176 and c0177 through f0147; c0196 and R0095 need f0147 anyway. Then state the fallback and its trigger: when f0143 and f0158 are otherwise ready and c0176 or c0177 is not `done/`, `./zn unfold R0094 f0147`, and R0094 goes ahead with two members. Say who decides (the rafter or lead, at z-ready time). This adds no spec case.
Lesson: z-raft/grouping-cost-checks-every-wait

### F2 [medium] No member's sequestered specs have run with the other members' code, the cross-reads are not named as interfaces, and two of the three prototypes are gone
Where: R0094.md, Experiments phase ("None at raft level"), Risks ("Each member's prototype was built without the others, so the first full gate on the merged tree is the real test"), Whole-raft design ("Between f0158 and the others (indirect)").
Evidence: these sequestered specs read code another member changes. The Whole-raft design names only the clear.spec and counter pair:
- f0158 `acceptance/place.spec.luau:70` builds `Session.new(classic, 1, Session.GAME_CONFIG)` and steps it 61 times to place the player. f0147 adds `GAME_CONFIG.ramp`, so that warm-up moves the player 21 units a step instead of 30. The Whole-raft design says DangerHud "shares nothing with the frame's new fields" but doesn't name this config read. By reading, it stays green: `ghostAt` searches the whole maze from whatever pose results, and the case replaces `snap.ghosts`. That is reasoned, not run.
- f0147 `acceptance/hud.spec.luau` loads HudView's real source. f0143 lands first and gives HudView a `Logic/Boost` require and a `Boost` label that `lay()`, `show` and `shots` re-lay. f0147 relies on its stub loader falling back for unknown Logic requires (its Unknowns, "stub-loaders-fall-back"). That has never run against f0143's HudView.
- f0143 `acceptance/hud.spec.luau`, and the shared `tests/place/hud-shots.spec.luau` it edits, will run on HudView with f0147's `Picks` label in the same `start`, `show` and `lay()`.
- Only f0147's `experiments/prototype.patch` survives. f0143's `proto-f0143-deps2` and f0158's `proto-f0158` exist neither locally nor on origin (`git ls-remote origin` and `git branch -a` show no `proto-f01*`), yet the raft cites them as the members' evidence.
Critique: a red case found during execution can't be fixed there. Neither executor may edit the other's sequestered spec, so the raft stops and a member is unfolded after a layer is already built. The author will be tempted to add "rerun on the merged tree", but that is what execution does anyway, so it adds nothing.
Consequences: a full merged run needs f0143's and f0158's prototypes rebuilt on the current origin/main, close to re-executing them. Naming the cross-reads costs only text. It gives each one a stated assumption, plus a rule for when the assumption fails.
Recommendation: in Whole-raft design, add an "Indirect spec reads" list with the three items above. For each, give the member whose code it reads, the property the spec relies on (pose-independent `ghostAt`; the stub loader's fallback to the real `@logic/<name>`; labels found by name, not by count or order), and the stop rule: a member's sequestered spec turned red by another member's code stops the raft, and the red member is unfolded back to z-design. Neither executor edits it. Say that RC0 runs all three `check.sh` files on the final tree, so wave 2's checks see f0143's code. If the author wants it proved now, apply f0147's `prototype.patch` to a scratch clone under `.cache/` (through `./zn run --time`) and run f0158's place.spec against it with f0158's DangerHud change. That pair needs no lost prototype except f0158's small DangerHud diff.
Lesson: z-raft/run-sequestered-specs-on-all-prototypes-together

### F3 [medium] The Exit criteria point to an RC1 in "the lead's report", which is not in the record, and the raft's claims about what execution proves have no RC line
Where: R0094.md, Exit criteria ("see the lead's report for a proposed RC1"); `check.sh` (only the commented `# check "RC1: …"` placeholder); Risks ("no spec runs a boost under the shipped ramp … the code review should confirm the speed line reads `Session.speeds`"; "The counter against the ring is pinned only by c0196 (backlog) after both land").
Evidence: the executor and `./zn done` read the raft document and `check.sh`, not a session report, so the proposed RC1 is lost. Two interactions are met only in this raft, and no check backs either:
- a boosted step on the shipped ramp. f0147's E1 and Regression guard, and this raft, state 32 units on level 1 (`round(1.5 × 21)`) and the tile cap on the capped levels. f0143's specs use their own ramp-less configs.
- the PICKS row against the ring. E8 measured it on a prototype. The pin is a backlog chore, c0196 (`design: draft`, `raft:` empty), that runs after both land.
Critique: an RC that checks nothing is the gap the lesson describes. The fix the author will reach for is to drop the "lead's report" sentence, which only hides the gap.
Consequences: an RC that runs a spec needs a home the runner and `promote-check` accept. A raft-owned spec has no precedent here: R0051's RC1 ran a member's own spec. Folding c0196 instead means prepping it through z-design first, and the fold changes the grouped record, so it needs its own coherence review (z-raft §4).
Recommendation: take one of these, and either way delete the "lead's report" pointer:
- (a) Add RC lines to R0094's `check.sh` backed by a raft-owned spec run through the spec runner (`lune run tests/run -- <path>`), once the author confirms `promote-check R0094` accepts its location. Cases: in a `GAME_CONFIG` session, a boost on level 1 covers 32 units in its first step (an implementation that boosts `Levels.playerSpeed` with no ramp gives 45 and fails); on a level where `round(1.5 × player) > 120` it covers exactly 120; and `Hud.picksBox(Touch.blocks(l).score)` clears `Awareness.ring`'s dots on f0158's 15 screens.
- (b) Prepare c0196 and fold it into R0094 for the counter pair, with (a) for the boost alone.
- (c) Record in Exit criteria that the two claims are unpinned until c0196, and why that is acceptable.
Lesson: z-raft/rc-pins-the-claims-it-makes

### F4 [low] The Experiments phase puts the boost's smallest ramped gain on the wrong levels
Where: R0094.md, Experiments phase ("the smallest gain is on levels 22 to 34 where the player is already near the cap").
Evidence: on `GAME_CONFIG` (ramp plus f0125's 1/1.1 tuning), a boosted player against a hunting ghost:
- level 1: 32 against 18 (f0147 ramp.spec: player 21, ghost 18). Level 2: 33 against 19. Both gain 14 units a step, 308 units (2.57 tiles) over 22 steps.
- the gain then grows to about 50 at level 29, where the boost first reaches the cap (`1.5 × 21 × 1.05^28 ≈ 123`).
- the gain falls back to 30 at level 34 (120 against 90).

So levels 1 and 2 have the smallest gain, not 22 to 34. It still clears f0143's E1 bar of 240 units. In a dotted corridor on level 1 it is about 225 units (1.9 tiles): `120 / 32 + 0.5 = 4.25` ticks a tile, 28.2 against 18.
Critique: the conclusion holds, but the reason the raft gives for running no raft-level experiment is wrong, and a later tuning of `Levels.RAMP.first` would read the wrong levels as the margin.
Consequences: none.
Recommendation: restate the sentence with these numbers: the smallest gain is levels 1 and 2 at 14 units a step (308 units, 2.57 tiles; about 1.9 tiles in a dotted corridor), above E1's 240.

### F5 [low] Stale or missing facts in the Whole-raft design and Order: f0147's game-design text is already on main, a second shared place spec is left out, and f0143's pre-z-ready E7 check is not carried
Where: R0094.md, Whole-raft design (`pickman/.tracker/game-design.md (f0143, f0147)`: "each adds its own section"; "f0143's `tests/place/hud-shots.spec.luau` edit … is the only spec edit to a shared place harness"); Order & dependencies.
Evidence:
- f0147's section "## Levels by picked walls (user, 2026-10-25; f0147)" and every restated line its docs.spec needs ("on f0147's ramp, 67 steps on level 1", "the shipped ramp's level 1 speed of 21 units", …) landed with its prep, e3eae83c (#191). Only f0143 writes game-design.md in this raft. f0143's Usability and G2 state level 1 as "45 units a step against a hunting ghost's 28". Those are the classic numbers; game-design.md already says the shipped game runs the ramp (32 against 18).
- f0143's Touched list also edits `pickman/tests/place/touch-adapters.spec.luau`.
- f0143's E7 says it is "checked … again before z-ready" (does Controls still hear swipes on `InputBegan`, `InputChanged`, `InputEnded` after d0151?). The raft's Order doesn't carry that step. It passes on this tree: `Controls.luau:188-196` still connects all three, and d0151 is done.
Critique: the executor follows the raft. If f0143's boost text copies the classic level-1 numbers into game-design.md, the text no pin catches contradicts the ramp sentence already there.
Consequences: none beyond the text.
Recommendation:
- Say that f0147's game-design text is on main (e3eae83c), so only f0143 adds a section, and that it states the boost relative to the level's speed (or gives both the classic and the shipped level-1 figures).
- Add `tests/place/touch-adapters.spec.luau` to the shared-harness sentence.
- Copy E7 into Order & dependencies as a pre-z-ready check, with today's result (pass: `Controls.luau:188-196`) and its fallback (a chore re-points controls.spec's touch stub).

Lesson: z-raft/member-handshakes-reach-the-order

Candidate lesson (z-design, for the lead to write): **a prep keeps its prototype as `experiments/prototype.patch` in the issue folder, never only as a branch or scratch worktree**. Why: R0094's coherence review found f0143's `proto-f0143-deps2` and f0158's `proto-f0158` gone by rafting time, so no merged run of the members was possible (F2). Only f0147's patch survived. Check: does every prep's Unknowns & experiments name a prototype artefact that is committed with the prep?

Verdict: changes
