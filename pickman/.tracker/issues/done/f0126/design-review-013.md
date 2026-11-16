# Review 013: f0126 (design mode)
Inputs: prep worktree prep-f0126-colours at d27b2bf3 plus its uncommitted changes (`git diff HEAD`: f0126.md, check.sh, game-design.md, acceptance/adapters, controls, parts and views specs, experiments/base.patch, prototype.patch, mutants.py, harvest.md, R0053.md, the z-design lessons in-flight-bases-pin-their-source, quote-other-preps-before-promising, spec-design-correspondence, shared-bars-cover-every-pair, the z-raft lesson rafted-member-changes-stay-in-the-raft); design-review-011/012 and design-refute-011/012; f0109's prep (prep-white-ghost-green-walls, now at 4cc59ded, one commit past dc2405a3); proto-f0109 (ee121ddc plus its working tree).
Dropped from design-review-012: F1, F2, F3, F4 (rulings below).

Rulings on refute 012:
- F1 fixed, as of dc2405a3. The recut base carries the user's (14, 64, 14) green, `fake.module`, the stricter `SetAttribute` and f0146's `Pad`; prototype.patch applies on it; E4, E6 and E12 cite dc2405a3 and the green's two dates. The source hash still matches proto-f0109 today. But f0109's prep has moved again since (F1 below).
- F2 fixed. The sending is recorded under "Other preps' records", and f0109 has since recorded the new gold itself (its 4cc59ded: G1 "31.4 from f0126's brighter gold (255, 215, 0)", E1, line 87). The f0126 sentence calling that text f0109's to update is now dated (F3).
- F3 fixed in the spec: the case checks `View.FRIGHTENED_COLOR` and `View.WHITE`, and V10 is killed by it (run below). check.sh's AC5 label says "ghost look". f0126.md's AC5 text does not (F2), contrary to the refute.
- F4 fixed in part, accepted as pending. R0053's Theme quotes "Brighter gold" and its Experiments line has 149 / 136 / 7. `grouped:` is still `[f0126@16379c5b5949]`: the refute puts the fold at the end of the branch, which is the lesson's order (fold after the last design change), so it is not a finding now. It must happen after this round's answers, not before them.

Evidence run (all in `$TMPDIR/rv013`; no ref changes, no fetch):
- `python3 pickman/.tracker/issues/f0126/experiments/mutants.py V9 V10` from the prep worktree: `refusing: proto-f0109 has moved (its specs) since base.patch was cut; cut the base again (E12)`.
- What moved: `git diff --stat dc2405a3 HEAD` in prep-white-ghost-green-walls: f0109's `acceptance/place.spec.luau` (+15/-1: MazeView's real level-clear flash, lit while not edible, white then blue; the radar walks seven wall states with (true, false) in them, f0109 design review 003 F1), plus f0109's own documents and lessons. No source change (the "its source" hash still matches).
- My run: a copy of mutants.py whose only changes are `HERE` pointing at the prep's experiments folder, the hash check skipped, and f0109's current `place.spec.luau` copied over the base's before the baseline. Result: **BASELINE 149 passed, 0 failed, 16 spec files**; **136 killed**, all on an assertion; **C1 to C7 green**; no SURVIVED, ANCHOR or LOAD ERROR (144 lines). V9 and V10 are killed by "the marks' gold stands at least 30 (CIE76) from every ghost and ghost look…". So f0126's MazeView passes f0109's new flash walk; only the record is dated.
- Promotion dry run on a clone at dc6c8bf1 with base.patch, prototype.patch and the 13 specs at `pickman/tests/acceptance/f0126`: `stylua --check` exit 0; `selene` 0 errors, 0 warnings, 0 parse errors; `luau-lsp analyze --base-luaurc=.luaurc --platform=standard` exit 0, no diagnostics.
- Colours in the recut View: Blinky (255, 0, 0), Pinky (255, 184, 255), Inky (230, 255, 0), Clyde (255, 184, 82), frightened (33, 33, 255), white, walls (33, 33, 222), edible (14, 64, 14), marked (255, 215, 0). `View.ghostColor` falls back to `View.WHITE` for an unnamed ghost, which the case covers.

### F1 [low] f0109's prep moved again (4cc59ded, its place.spec's flash walk), so the runner refuses and E4, E6 and E12's "as of dc2405a3" is one commit out of date; E12 still lacks the "recut whenever f0109 moves" sentence (repeat of design-review-012 F1, smaller)
Where: `experiments/mutants.py` `F0109_SPECS`; `experiments/base.patch` (its copy of `tests/acceptance/f0109/place.spec.luau`); f0126.md E4, E6, E12; R0053.md Experiments.
Evidence: the refusal and the run above. Only the spec hash moved; with f0109's current place.spec the numbers are the same as recorded (149; 136 killed; 7 green).
Critique: severity is low because I reproduced every recorded number on f0109's current state, so neither the executor nor the game is affected. But it is the second round running where f0109's review moved under this prep, and this is the mechanism, not a hole in it: f0109 is still in review (its round 003 just answered), so any recut is dated by f0109's next round. The author will be tempted to bump `F0109_SPECS` only. That leaves base.patch running the old place.spec in the baseline, so the hash would claim a check that isn't run.
Consequences: a recut today can be dated again by f0109's round 004. Nothing in f0126's design depends on which f0109 round is current, as long as the last recut before landing passes.
Recommendation: make the recut the last step before this prep lands (the new check in in-flight-bases-pin-their-source): replace base.patch's copy of f0109's `place.spec.luau` with the prep's current file (proto-f0109's source needs nothing), update `F0109_SPECS`, rerun the runner, and write E4, E6 and E12 against the f0109 commit actually cut from (4cc59ded or later). Add to E12 the sentence review 012 asked for: the base is recut whenever f0109's prep moves before this prep lands. R0053 already has the matching sentence; refresh its "dc2405a3" too.
Lesson: z-design/in-flight-bases-pin-their-source

### F2 [low] AC5's text in f0126.md omits the ghost looks the case now checks
Where: f0126.md AC5 ("the gold stands at least 30 (CIE76) from every ghost colour and from the walls' blue and green"); check.sh AC5 label and the parts.spec case name say "ghost look".
Evidence: `grep -n "^- AC5" f0126.md`, quoted above. refute 012 F3 says "AC5's text and its check.sh label say 'ghost look'": only the label does.
Critique: the criterion text and the check it names disagree on what is checked.
Consequences: none.
Recommendation: add "and look (the frightened blue, the blink's white)" to AC5's text.
Lesson: z-design/restated-rules-move-together

### F3 [low] "Other preps' records" says f0109's text still quotes the old gold and 45.4; f0109 has since updated it
Where: f0126.md "Other preps' records", the sentence added for design-review-012 F2.
Evidence: f0109.md at 4cc59ded line 87 ("gold (255, 215, 0) since the user's 'Brighter gold'"), line 164 (G1: "31.4 from f0126's brighter gold"). `grep -n "191" f0109.md` still hits line 73 (E1's history clause, "then (255, 191, 0), since 2026-10-26 (255, 215, 0)"), which is correct history. G1 still gives yellow as "only 23.1 from the gold", the old gold's number (8.8 from the new); that's f0109's text, and its decision holds either way.
Critique: the record says f0109 hasn't done something it has done.
Consequences: none.
Recommendation: say f0109 recorded the new gold in its 4cc59ded (G1, E1), and optionally pass on that G1's yellow figure is the old gold's.

Repository safety: the change adds no command. mutants.py writes only inside its `$TMPDIR` clone (`inside_clone`) and reads proto-f0109 and f0109's prep with `git diff` and `open`. My runs were all in `$TMPDIR/rv013`.

Scope: `./zn capture f0126` (add831e3). This round's diff changes no Problem outcome, Solution idea or Non-goal beyond review 012's approved `Decided with the user (2026-10-26)` "Brighter gold" line. Every captured outcome keeps its criterion.

Overrides: no new Touched path. game-design.md gains one line (approved in review 012). origin/main has moved past this branch's base (its f0024 and f0026 adapter spec edits, c0128's golden), but those are main's, not this prep's. Whether they meet f0126's Touched adapters is the base-update question the prep answers when it merges main before landing; nothing in this round's change touches them.

Lessons pass: I asked the design lessons' checks (`./zn lessons --when design`) of the changed sections. restated-rules-move-together → F2; in-flight-bases-pin-their-source → F1; shared-bars-cover-every-pair: met (every ghost, both looks, both wall colours); spec-design-correspondence: V9 and V10 are each killed by the new case. The lesson notes added since round 012 (harvest.md) are general checks: the pre-land hash check, sending a changed shared number to the prep that quotes it, and "delete the case, does its mutant still die". None restates a finding.

Lesson candidates (for the lead):
- z-design/in-flight-bases-pin-their-source, a note: while the sibling prep is still in review, recut once, as the last step before landing, not in each round. Each round's recut is dated by the sibling's next round. Check: is the recut the last commit before the prep's PR, and does the runner pass at that commit?
- z-raft/rafted-member-changes-stay-in-the-raft, a note: the re-fold comes after the final round's answers, so `grouped:` hashes the approved text. Check: does `grouped:` match the member's document as approved?

Verdict: approve
