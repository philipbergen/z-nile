# Review 002: R0094 (raft mode)
Inputs: raft-stack-dependencies at e0496e5e6703 (R0094.md last changed in 88a54fb3d); `pickman/.tracker/rafts/R0094/R0094.md` and `check.sh`; the members' documents, `check.sh` and `acceptance/` (f0143, f0147, f0158, f0148) and f0147's and f0148's `experiments/prototype.patch`; retired `R0095.md`; `./zn workstreams R0094`; `./zn stack R0094`; `./zn find` on every member's `depends_on` and on every non-done item that depends on a member; `origin/prep-paid-play-and-continues` (f0145); `pickman/.tracker/game-design.md`, `architecture.md`, `src/shared/Logic/Session/init.luau`, `Game/init.luau`, `Ghosts/init.luau`, `src/client/Controls.luau`; `z-nile/engine/stack.luau`, `readycheck.luau`, `readyfacts.luau`; the z-raft lessons.
Grouped: [f0143@9de19e99185d, f0147@deb99c51e2b8, f0148@d09fb2e83d5c, f0158@59277d5ddbf9]

These hold, so they are not raised:
- `./zn workstreams R0094` puts f0148 in wave 3, after f0147 (`depends_on`).
- `ready` treats a `depends_on` on a member as met (readycheck.luau:204-214).
- The three older hashes in the record equal design-review-001's. f0148's equals the hash in retired R0095.
- f0148's `Game.new(config?, ramp?, start?)` and `Session.join(s, id, start?)` extend f0147's prototype lines exactly (f0148 `prototype.patch`, the Game and Session hunks). `Ghosts.Options.level` exists (Ghosts/init.luau:46).
- No other non-done item extends `Session.join` or `Game.new`.
- f0147's levels.spec sets `start` by hand ("f0148 sets the start"), so it agrees with f0148's `Game.new`.
- No sequestered spec of f0143, f0147 or f0158 reads f0148's lobby or server adapters.
- Among non-done items, only c0188 (draft) names f0148's lobby paths, and it records that the portal must carry the picker.
- f0143's E7 still passes on this tree (Controls.luau:188-196).
- f0148's docs.spec needles hold on main: "(1 until f0148)" is gone, and "(picked in the lobby, f0148)" appears exactly twice.
- RC0 picks f0148 up through `./zn members`.
- No other raft document names f0148.

### F1 [high] The rewritten Order section names every member several times, so `stack.order` refuses R0094 and `./zn start` cannot open its first layer
Where: R0094.md, `## Order & dependencies` (lines 79-86), above all the reasons paragraph at line 85 and the claim at line 86.
Evidence: `./zn stack R0094` (read-only) prints `f0143 is listed twice in R0094's Order` and exits 1. `layergit.orderedMembers` hands the whole section, up to the next `## `, to `stack.order` (z-nile/engine/stack.luau:198-214). That function collects every `[fdc]%d%d%d%d` in it and refuses a repeat.

The section names:
- f0143 twice;
- f0147 six times;
- f0158 three times;
- f0148 five times.

The names come from three places:
- the numbered list;
- the reasons paragraph: "f0143 first ... f0147 second (it sets the ramp and `Game.start` that f0148 uses). f0158 shares no Touched path with f0147 ... f0148 last, because it `depends_on` f0147";
- the workstreams quote: "for f0158 and f0147".

Line 86 then says "This section names only members, each once". The Order before 88a54fb3d named each member once. `./zn status R0094 prepared` and `./zn ready` don't run `stack.order` (lesson below). So the raft would be readied and then refused by `./zn start R0094`, and by `finish`, `commit` and `done`. Repairing it at that point takes `./zn stop R0094`, a rafting PR and a new `ready`.
Critique: The fix the author will reach for is deleting the parenthetical workstreams quote. That leaves the reasons paragraph, which still repeats every id.
Consequences:
- The order's reasons must survive without ids. Either write them with no item id ("the boost layer", "the ramp layer", "the ring layer", "the start layer"), or move them out of the section.
- The workstreams line cannot be quoted inside the section any more. Its last line is now `parallel: yes (wave 2: f0147 f0158)`, which names two members.
- Text under any later `## ` heading is outside the cut, so ids are free there.
- The edit leaves `grouped:` unchanged, because the record hashes the members, not the raft document. This review's record still covers the raft.
Recommendation:
- Keep the numbered list (1. f0143, 2. f0147, 3. f0158, 4. f0148) as the only text in the section that names an item.
- Move the reasons and the `./zn workstreams` line to a new heading placed right after it (for example `## Why this order`), or into Whole-raft design. Keep line 86's rule, which is then true.
- Run `./zn stack R0094` and quote its output in the refute. It must exit 0 and list the four layers in that order.
- No spec case is needed.
Lesson: z-raft/order-names-members-once

### F2 [medium] f0148's live-place checks (E6, E5) now gate the whole raft before `ready`, but nobody is named to run them and no result or unfold fallback is recorded, and its own fallback can't be applied because its spec pins the waits
Where: R0094.md, Cross-raft waits: "Phase 1 checks that wait for a live place" (line 101), "What grouping costs" (95), "Fallback, and who takes it" (97), "Waiting on this raft" (103). Risks: "DataStore behaviour" (121). f0148.md E6 (line 126) and E5 (128). f0148 `acceptance/adapters.spec.luau:224` and `:285`.
Evidence:
- **Nobody can run them as written.** Line 101 says E6 and E5 "run before `ready` with API access on or in the runtime suite". Both need f0148's code running in Roblox:
  - E6: the lobby's write and the game place's claim against a real DataStore.
  - E5: the attribute replicating, and the arrows on a phone.
  Before `ready` no published place runs that code: the runtime suite runs on the CICD places that `scripts/cicd` publishes at a merge (pickman-test, `tests/runtime/`). No result is recorded in either document. Nobody is named to run them, and a Studio test with API access is a human's step.
- **The fallback can't be applied.** f0148's E6 fallback is `Bests.WAIT` raised to 20 s, then a second key `<userId>/next`. But `adapters.spec` pins `t.expect(mod.WAIT).toBe(10)` (line 285) and `t.expect(mod.CHOOSE_WAIT).toBe(5)` (line 224), and AC4's label says "silent for 10 s". An executor who follows zz-execute Phase 1 ("Switch to the documented fallback") turns AC4 red. A second key changes the claim those cases pin. So either fallback is a re-prep of f0148. Risks line 121 ("the fallbacks are in its design") reads as if the executor could apply them.
- **Grouping cost.** "What grouping costs" names only c0176 and c0177, and the fallback paragraph covers only those two chores lagging. Through this raft, f0143, f0147 and f0158 now also wait for f0148's layer and for these live checks. So do d0149 and c0182, which need f0143 and f0158 but not f0148. c0342 (`depends_on: [f0147, c0177]`, backlog) is missing from "Waiting on this raft".
Critique: The fix the author will reach for is dropping "before `ready`" and leaving E6 and E5 to Phase 1. Phase 1 runs after `ready`, but it needs the same thing: a Roblox place running f0148's code, which no layer has at that point. A failure there stops all four layers.
Consequences:
- A result recorded in f0148.md before `ready` changes f0148's design hash. `./zn ready` then refuses the raft ("changed on origin/main since R0094 grouped it") until f0148 is folded again and a new coherence review runs. A result recorded before `ready` belongs in R0094.md.
- A failure after `ready` costs more: `./zn stop R0094`, `./zn unfold R0094 f0148` in a rafting PR, and a new `ready` for the other three. `unfold` refuses a member of an active raft.
- Running them before `ready` needs the user (Studio with API access on). If the user declines, the unfold fallback below applies.
Recommendation:
- In Cross-raft waits, give E6 and E5 one place, one actor and one failure path. Pick one of:
  - (a) Before `ready`, the user runs them in Studio with API access on, on f0148's `experiments/prototype.patch` applied in a scratch worktree, and the result is recorded in R0094.md (not f0148.md). If they fail, or are not run when everything else is ready, the lead first runs `./zn unfold R0094 f0148`, as the c0176/c0177 fallback does for f0147, and the raft goes ahead with three members.
  - (b) They move to after the merge, in Beta beside f0148's OC1, and a failure there becomes a follow-up issue. f0148's design asks for them before `ready`, so this needs a `Decided with the user` line.
- In Risks, say that both documented fallbacks are a re-prep of f0148, because `adapters.spec` pins `WAIT = 10` and `CHOOSE_WAIT = 5`.
- Under "What grouping costs", add that f0143 and f0158, and their dependents d0149 and c0182, now also wait for f0148's layer and these checks.
- Add c0342 to "Waiting on this raft".
- No spec case is needed.
Lesson: z-raft/grouping-cost-checks-every-wait

### F3 [medium] f0147's recorded rule that every level from level 2 on has the bonanza's longer jumps becomes false for a run f0148 starts on level 2 or later, and nothing says what such a run gets
Where:
- game-design.md:101: "Since every level ends with a bonanza, every level from level 2 on has the longer jumps, so from level 2 a rolled longer-jumps boon shows its banner and adds nothing". f0147's docs.spec pins "a rolled longer-jumps boon shows its banner and adds nothing".
- game-design.md:108 (f0148): "The run starts on the picked level and plays it as f0147's ramp has it: its speeds, its multiplier, and the extra life".
- f0147.md Behaviour 6, and its "Keep it, record it" decision (line 36).
- f0148.md Behaviour 7.
- R0094.md Whole-raft design, **`Logic/Game` and `Logic/Session` (f0147, f0148)**.
Evidence:
- f0147 grants the long hops and the long ghost pill on `Ready reason = "level"`, from the `member.bonanza` that the tenth pick set (f0147 `prototype.patch:660`). f0147's join starts a member with `bonanza = false` and `bonanzaPill = false` (`prototype.patch:602-603`), and main's join sets `longHops = false` (Session/init.luau:263). f0148's prototype changes only the `Game.new` and `Ghosts.new` calls in `join`.
- So a run started on level 5 plays level 5 with neither, while a run that reached level 5 by play has both. On that started level, a rolled longer-jumps boon does grant long hops.
- The user's "Keep it, record it" (f0147, 2026-11-01) was put on the premise that such a boon "adds nothing there".
- `grep -n -i "bonanza\|long hop" f0148.md` finds nothing.
- Each sentence passes its own pin, yet the merged text contradicts itself.
Critique: This is a product question where two members meet, and neither member's design owns it. The fix the author will be tempted by is letting f0148's executor qualify line 101 on the fly, which makes the product choice without the user.
Consequences:
- (a) **No carry on a started level** (the prototypes' behaviour). The bonanza line needs a qualifier, for example "every level reached by play from level 2 on", written by f0148's layer. The qualifier must keep f0147's needle as one unbroken substring. It must not add a third "(picked in the lobby, f0148)", which f0148's docs.spec counts as exactly 2. The behaviour stays unpinned unless f0148 gains a case, and that would be a re-prep.
- (b) **The carry on a started level.** A run started on level 2 or later begins with the long hops all level and the long pill after READY. That changes f0148's `Session.join` and its sequestered specs: `./zn unfold R0094 f0148`, and f0148 goes back to z-design.
Recommendation:
- Put the question to the user as one bullet under `## Open to the human`, with options (a) and (b) and the costs above, and record the ruling in the Theme as a `Decided with the user` line.
- Under (a), name the qualifier in Whole-raft design's game-design.md paragraph as part of f0148's layer, and list the started-level behaviour under Exit criteria as an unpinned claim, as the boost-on-the-ramp claim is.
- Under (b), unfold f0148.
Lesson: z-raft/merged-text-read-against-captures

### F4 [low] The Theme quotes "3 rafts in order" as a decision f0147 and f0148 rely on, and both members say "The work lands as sequenced rafts", but nothing says the 2026-11-15 request replaces it
Where: R0094.md Theme, lines 17, 19, 33 and 35; f0147.md:26 and f0148.md:22.
Evidence:
- This record lands f0147 and f0148 in one PR.
- Line 19 quotes the 2026-11-15 request ("stack the dependencies in rafts"), and line 17 reads it as "a dependent issue is stacked in its dependency's raft as a later layer". The retired R0095 had already stacked f0148 after R0094, but as a separate raft.
- Lines 33 and 35 then quote the old decision as one the designs rely on, with no word of how the two fit. The order (f0126, then f0147, then f0148) still holds, as layers.
Critique: An executor reading the members finds "sequenced rafts" contradicted by the raft, with no ruling.
Consequences: none beyond the text. No member's document changes (z-raft never edits one).
Recommendation: Under the Theme's 2026-11-15 line, add a sentence saying the request replaces the packaging half of "3 rafts in order". f0147 and f0148 now land in one PR, still in that order, as layers, which holds f0143 and f0158 behind f0148's layer (F2). If the lead cannot say that the user meant this, put it under `## Open to the human`.

### F5 [low] Stale or wrong facts about f0148 and the files the members share
Where and Evidence:
- **f0148's documents are already on main.** Whole-raft design's game-design.md paragraph (line 63) says f0148's section "lands with its layer". The architecture.md paragraph (line 65) says "f0148 adds the `Best` row". Both landed with f0148's prep (901f1e67b, #216): game-design.md:105 and architecture.md:21. f0148's Implementation step 3 says "(in prep)". An executor who writes them again duplicates the restated lines f0148's docs.spec counts.
- **f0145's edge is on its prep branch.** Waiting on this raft (line 103) says nothing enforces the order. But f0145's `depends_on: [d0124, f0148]` is committed on `origin/prep-paid-play-and-continues` (c746326c), and f0145 is `preparing-indigo-marble-marble` on main, so the edge arrives with its prep. Nothing enforces it only if a new prep of f0145 starts from main.
- **Two members do change the same functions.** Line 38 says "No two members add or change the same function, type or table, with one exception". In fact f0143 and f0147 both add fields to `Member` and both edit `Session.step`, `HudView.start` and `HudView.show`, as the raft's own HudView paragraph says.
- **The Risks counts are wrong.** Line 119 says "Four members edit `Session`". Three do (f0143, f0147, f0148). `Game` has two (f0147, f0148), and `Hud`/`HudView` two (f0143, f0147).
- **The Data flow misses a client argument and misattributes an event.** Line 77 leaves out that the lobby client now sends the level as an argument on the existing StartGame remote (`StartGame:FireServer(level)`), which `Best.choose` bounds. It also calls the `Ready` event with reason `level` "f0147's". That event exists on main (Game/init.luau:187); f0147 changes when it fires.
- **f0148's indirect reads leave out f0143.** Line 75 names only f0147's code. f0148's specs also run on f0143's Session (the member record's `boost` and `boosted`, and `Boost.speed` around the step's speed), as the layer above f0158's. They stay green by reading: no f0148 case sends `Boost`, and an inactive `Boost.speed` returns the speed it was given (f0143.md:65).
Critique: An executor follows the raft's facts; each one above sends them to the wrong file or the wrong expectation.
Consequences: none. No member changes, and no spec case is added.
Recommendation: Correct each sentence as listed.

Verdict: changes
