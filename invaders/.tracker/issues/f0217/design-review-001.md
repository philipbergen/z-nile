# Review 001: f0217 (design mode)
Inputs: prep worktree `prep-invaders-two-players` at 6c28abad plus its uncommitted item folder (`f0217.md`, `check.sh`, `acceptance/{field,flyin,crossing,sides,survivor,match}.spec.luau`, `experiments/{prototype.patch,mutants.py,bench.luau}`); f0216's prep head `a19b4281` (`origin/prep-invaders-classic-rules`, its prototype and seven specs); `./zn capture f0217` (capture d7714681); `invaders/.tracker/game-design.md`; f0218's and f0219's captures; `pickman/tests/meta/architecture.spec.luau`.
Reruns: both prototypes applied in a `mktemp -d` clone: f0217's specs 44 passed, 0 failed. `./zn run --time 1500 -- python3 -I invaders/.tracker/issues/f0217/experiments/mutants.py`: base green, 81 mutants killed, 7 correct variants green (E2 reproduced). `stylua --check` clean on the item folder and on the prototype's `src/shared/Logic`. `lune run z-nile/affected -- <touched paths>` prints nothing; `grep -rlF` of `Logic/Classic`, `Logic/TwoPlayer`, `TwoPlayer` over every `tests/acceptance` finds nothing (`Classic` alone matches only pickman's `Ghosts/Classic.luau` watch lines). I ran nine more mutants of my own on the same clone (one probe script, bounded), listed under F1 and F3; all nine survive the six specs (44 passed each).

### F1 [high] The fly-in's shot cases fire only player 1's shot at player 1's places, so three wrong fly-in hit rules pass AC2
Where: `acceptance/flyin.spec.luau` :: "lets the players shoot the aliens as they fly in" and :: "lets a shot through a place whose alien is still on its way"; Design, One tick, step 3 (the flyer test "at the field point `toField(p, x, d)`" and "a living, not waiting alien of p's group at `(x, d)`, then of o's at `(x', d')`"); Rules rows Y9, Y11.
Evidence: both cases set only `g.sides[1].run.shot` (the first loops over the target flyer, never the shooter), and the second only sends player 1's shot through player 1's own waiting place. With both prototypes applied, each of these leaves all 44 cases green:
- MA, flyers tested in the shooter's own frame: `if shot.x >= x0 and shot.x < x1 and shot.d >= d0 and shot.d < d1 then` for the `fx`/`fd` test. Player 2's shots then hit flyers at the mirror image of where they are.
- MB, the other group's waiting places can be hit: `if row and col and (q ~= p or not g.sides[q].waiting[...]) then`. A shot crossing the field during the fly-in kills an alien that hasn't arrived yet, so it is invisible.
- ME, player 2's waiting places can be hit by player 2: `(p == 2 or not ...waiting...)`.
In each one AC2's "can be shot on the way" and Y11's "a waiting place passes shots" are wrong for half the shooter × group pairs.
Critique: the hit code walks two sets, shooters {1, 2} and groups {own, other}, and only one of the four pairs is pinned. The tempting fix is to add a player-2 loop to the first case and stop there. That catches MA but not MB.
Consequences: the new cases have to place a shot where no flyer can take it first. At tick 1 or 2 every flyer is still on the lane at the field's east edge (x ≥ 206), so a shot at x 168 crossing toward player 2's front-left place is clear. A shot through the other group's place travels ~80 ticks from a cannon, so set it just short of the place, as crossing.spec's cases already do. No rule changes.
Recommendation: three cases or assertions, each with a row run in `mutants.py`:
- Y20 "flyers are hit in the field's frame, for either shooter" (kills MA): after 8 ticks player 1's flyer is at field `[170, 182) × [228, 236)` once it moves. Player 2's shot goes at their `(W − 1 − 175, D − 1 − 237)`. Expect `AlienHit` with `shooter = 2` and `player = 1`, player 2's score 10, the flyer out of `flyers`.
- Y21 "the other group's waiting places pass shots" (kills MB): at tick 1, player 1's shot at `(168, 334)` crosses player 2's waiting front-left place (field `[162, 174) × [336, 344)`). No `AlienHit`, player 2's `live` 40, the shot at `d = 338`.
- Y11 extended to both shooters (kills ME): player 2's shot through player 2's own waiting place, mirroring the existing case.
Lesson: zz-test/seed-every-enumerated-case

### F2 [medium] A player who is dying when the other clears the wave stays "dying" through the wave pause and comes back with no `Respawn`; the Design says nothing about it
Where: Design, One tick, step 4 and "`waveclear`"; The wave's start (`Classic.startWave(run)` sets `phase = "playing"`); the events table (`Respawn`: "step 2, the tick a dying pause ends"); Edge cases ("a respawn is the dying pause").
Evidence: my probe on both prototypes. Player 1 is hit (`dying`, timer 120, lives 2), then player 2 shoots the last alien. The events are `1:AlienHit:2 1:GroupClear:2 1:WaveClear 121:WaveStart 298:Formed …`. `phaseOf(1)` is `"dying"` with its timer frozen at 119 for all 120 ticks of `waveclear`, then `"playing"` after `WaveStart`. No `Respawn` is ever emitted for player 1. In solo this can't happen (dying pauses the whole game), so f0216 has no rule for it.
Critique: the Design says "The events are the one channel f0218 renders and sounds from", but here the cannon comes back with no event naming that player. f0218 would have to guess it from `WaveStart`. The checklist's "simultaneous events … a player who … respawns" isn't answered for this pair. The tempting fix is a sentence saying "the wave's start respawns them" with no event and no case.
Consequences: the rule has to say three things: whether the dying timer counts during `waveclear`, which event marks the return, and where that event comes in the tick's order. The solo 2 s pause is still always served. The clear comes before any bomb (step 4 before 5), so the hit is at least one tick before the clear, and the wave pause is 120 = `dyingTicks`. A second source of `Respawn` goes into the events table. sides.spec's existing `kinds(start) == { "WaveStart" }` has nobody dying, so it stays as it is.
Recommendation: state it as a prep choice. Suggested wording: the pause does not count during `waveclear`, and the wave's start ends it, emitting `Respawn { player, lives }` right after `WaveStart`. Add row S23 and a sides.spec case: player 1 hit, player 2 clears the wave on the next tick. Through the pause `phaseOf(1) == "dying"`. The ending tick's known kinds are exactly `{ "WaveStart", "Respawn" }` with `player = 1`, `lives = 2`, cannon at `cannonStart`. Mutant: no `Respawn` at the wave's start. Run it in `mutants.py`.

### F3 [medium] Five rules the Design states have no row and no case: each wrong version passes all six specs
Where: Design, "A player out" ("their bunkers stay on the field (still a target, untouched by the wave's start)"); `TwoPlayer.revive` ("`Classic.startWave(run)` with the run's own config (the group's size is the wave's)"); `TwoPlayer.retire` ("score, revives, lives and `reason` stay for the boards"); step 3 ("o is hit … o acts no more this tick"); the events table (`Formed`: `wave`).
Evidence: each mutant below, applied alone to both prototypes, leaves 44/44 green:
- MC: an out player's bunkers renewed at the wave's start (`else side.run.barriers = Barriers.new(side.run.config.barriers)` in the wave's start).
- MC2: retire wipes them (`run.barriers = { layout = …, blocks = {} }`).
- MD: revive re-derives the size from who is left (`side.run.config = if liveSides(g) == 1 then g.config.lone else g.config.pair` before `Classic.revive`). A player revived after the other retired mid-wave gets 5 × 11 instead of the wave's 5 × 8.
- MH: retire sets `lives = 0`, `reason = nil`, `revives = 0`. f0219's boards read `revives`, and "every board shows revives used" is the user's decision. survivor.spec asserts only `score` after a retire.
- MG: a player hit by a shot (`shotsHitPlayers`) keeps `acting`: the crossing case runs under `quiet`, so a march or fire by the hit player's group on that tick is never looked for.
- MF: `Formed` without `wave`: every case reads only its kind.
Critique: z-design's Rules and mutants rule is one row per behavioural rule. These are stated, plausible to get wrong, and two of them (MH, MD) are values another issue reads.
Consequences: none beyond the cases. Each rule is already in the Design.
Recommendation: one case or assertion each, with rows run in `mutants.py`:
- V11: erode player 2's bunker 1 at column 1 (3 blocks, as in crossing.spec), retire them, clear the wave. After `WaveStart`, player 2's count is still `4 × 48 − 3`, and a survivor's shot at that bunker gives `BarrierHit { player = 2, shooter = 1 }`.
- S24: player 2 retires mid-wave, player 1 goes to game over and is revived: `cols` 8, `live` 40.
- V12: player 2 revived once, then at game over again, then retired: `revives` 1, `lives` 0, `reason` `"lives"`.
- X21: with `shotsHitPlayers`, player 2's march due on the tick player 1's shot hits them: no `March` for player 2 that tick.
- `Formed.wave` asserted in flyin's "forms both groups in about 3 s".
Lesson: z-design/spec-design-correspondence

### F4 [medium] The four new dependency edges and TwoPlayer's Features row are left for the executor, against z-design step 2
Where: Implementation step 3 ("This prep decides the edges but leaves the file alone"); Design, The split; z-design SKILL.md step 2 ("Any new dependency edge goes in the project's architecture map … now, including the ```` ```deps ```` block").
Evidence: on `main` the deps block holds only `# no features yet`. f0216's PR #393 replaces that line with its three edges and adds the Features table. The reason given is that an edit here would conflict with #393. But this prep already can't stand before #393: `depends_on: [c0184, f0216]`, and E2's runner reads f0216's prototype from that branch or `main`. And the meta spec accepts a declared edge before its feature exists: it takes features from `src/shared/Logic`'s folders and checks only that the requires used are declared and that the graph has no cycle.
Critique: the map is what f0218's and f0219's preps, and z-raft's coherence review, read to see what TwoPlayer depends on. While TwoPlayer's edges live only in this document, that map is incomplete for every prep that lands meanwhile. The tempting fix is to keep the deferral and add a sentence. That still breaks the rule.
Consequences: the prep PR merges after #393. If #393 changes those lines again first, this prep rebases. Implementation step 3 becomes "confirm the four edges and the row are there". The edit isn't an override: c0183's `designs.spec` reads `invaders/.tracker/architecture.md`, but it accepts any version from the file's history.
Recommendation: once #393 has merged, add these to this prep as insert-only lines:
- `TwoPlayer -> Classic`, `TwoPlayer -> Formation`, `TwoPlayer -> Barriers`, `TwoPlayer -> Mystery`, after f0216's three edges;
- TwoPlayer's row, after Classic's.
If it must land first, base the prep PR on #393's branch instead. Either way, rerun `lune run tests/run -- tests/meta/architecture.spec.luau` from `invaders/` on main plus the edit (green with no TwoPlayer folder) and record it.

### F5 [medium] The calls that keep a match moving are promised for f0218 and f0219 only in this document; if one is missing, the wave never ends
Where: Non-goals ("f0219, which calls `TwoPlayer.revive`, and `TwoPlayer.retire` when the offer ends unbought"; "f0218's place calls `TwoPlayer.retire`"); The split; prep choice 6 ("A game over waits for the revive").
Evidence: neither `invaders/.tracker/issues/f0218/f0218.md` nor `f0219/f0219.md` mentions `TwoPlayer`, `retire` or a two-player game over. f0219's capture says only "game over (including invasion) offers the 1 R$ revive; game over returns to the portal". Under prep choice 6 the wave can't end until the waiting player is revived or retired. survivor.spec's own case shows it: 50 ticks with every alien gone and no event, then `WaveClear` on the first tick after `retire`. An offer that is dismissed or times out without a `retire` call leaves the survivor's match stuck forever. Prep choice 6 states no cost for this.
Critique: lesson z-design/quote-other-preps-before-promising: "A constraint one prep puts on another goes into the other item's own document, as a dated decision line, in the same round." Neither f0218's nor f0219's designer reads f0217's Non-goals.
Consequences: f0219's design then has to say when a two-player offer "ends": declined, timed out, or the player leaving, which also goes through f0218. A bounded wait in the rules (a `reviveWaitTicks` after which the match retires the player itself) would be another way out. It would be a new prep choice with its own row and case, and it overlaps f0219's ownership of "when it ends", so it is not the default here.
Recommendation:
- Add a dated line to f0218's and f0219's documents, under their Solution, naming the calls: `TwoPlayer.retire` on leaving (f0218); `TwoPlayer.revive` after the purchase and `TwoPlayer.retire` on every way the offer ends unbought (f0219). The line also says that without them the wave waits without limit.
- Add that cost to prep choice 6.

### F6 [low] `retire` emits no event and wipes the group's grid, so the fly-off can be drawn only from the client's last copy of it
Where: Non-goals ("the fly-off's animation … (f0218's view, from the state and events below)"); prep choice 8; `TwoPlayer.retire` ("every alien of their group is gone from play (killed …)").
Evidence: after `retire` the state holds `out = true` and an all-dead grid, and no step returns an event for it. Which aliens flew off survives only in what the view last replicated.
Critique: the line says the view works "from the state and events". For this one effect it has to work from the state before the call.
Consequences: none for the rules.
Recommendation: say it in The split: f0218 animates the fly-off from the grid it replicated before `out` turned true. Also say that `retire` leaves `formation.x`/`d` as they were (the prototype does), so the view knows where the group stood.

### F7 [low] E4's probe was neither kept nor run bounded, so the tick counts it reports can't be rerun as recorded
Where: Unknowns, E4 ("a probe stepping each wave 1 to 9"); prep choice 2 ("Every wave forms in 174 to 185 ticks"); zz-review design item 12.
Evidence: E4 names no file and no `./zn run` command. E1, E2 and E3 each record theirs.
Critique: the 2.5–3.5 s band is now pinned by AC2 and AC5, so the risk is small. But the exact numbers in a prep choice should come from a run anyone can repeat.
Consequences: none.
Recommendation: record E4's bounded command, or keep the probe as `experiments/flyin-ticks.luau`, run with `../zn run --time 60 -- lune run …` from `invaders/`, and note the command in E4.

Verdict: changes
