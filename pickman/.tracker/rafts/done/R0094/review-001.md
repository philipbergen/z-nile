# Review 001: R0094 (code mode)
Inputs: the four layers, each against the one below: `R0094/1/f0143` 611776e1dade (against origin/main's merge base df6859dbf), `R0094/2/f0147` 2a03b63e7e85, `R0094/3/f0158` 156a5ef9b107, `R0094/4/f0148` d268d1469c8a (HEAD; origin/main was 58a574506a55 at the fetch). The raft document and its check.sh; f0143.md, f0147.md, f0158.md, f0148.md with their check.sh files and sequestered specs.

Run by the reviewer on HEAD:
- `z-nile/check.sh --affected`: format, lint (0 errors), both type stages and both builds clean; pickman 1813 passed, 0 failed, 261 spec files; GATE PASSED. No tripwire.
- `./zn check f0143` 7/7, `./zn check f0147` 6/6, `./zn check f0158` 4/4, `./zn check f0148` 6/6.
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD` over the trackers' check.sh and acceptance paths lists only the four `acceptance/watch.txt` additions, which `./zn finish` writes (zz-review/finish-watch-is-generated). No check.sh or sequestered spec changed.
- Nine mutants run on the landed code in a detached throwaway worktree (removed afterwards), each against its sequestered spec, all killed on an assertion: Controls folding swipes into `keyTaps` (f0143 controls), a Boost that queues no Forward and a step that never boosts (f0143 session), the counter placed by `blocks.level` (f0147 hud), the bonanza without its pill (f0147 levels), `Bests.reached` on any Ready and `Sessions` without its post-wait recheck (f0148 adapters), `Ghosts.new` without `level = start` (f0148 session), the ring lit by every ghost (f0158 ring). This was done because f0143's executor wrote the source before running its specs (its deviation 1): the specs do bite on the code as landed.
- The raft's Exit criteria ask this review to confirm the step's speed line: `Session/init.luau:731-735` is `Boost.speed(Session.speeds(s.config, member.play.level, frightened).player, Boost.active(member.boosted, s.tick), Movement.UNITS)`, before f0126's pick cap (lines 746-752). It reads `Session.speeds`, not `Levels.playerSpeed`, so the ramp reaches it. Confirmed.
- Repository safety: the diff adds no check.sh, no script and no spec that runs a process or writes outside the runner's jail; the two place harnesses only gain a module entry and an `os.clock` stub; no guard file is touched. Bounded commands: nothing in the diff starts a process.

### F1 [medium] f0148's live-place experiments E5 and E6, which the raft made a precondition of `ready`, were never run, and the layer records "Deviations: none"
Where: `pickman/.tracker/rafts/active/R0094/R0094.md` (Cross-raft waits, "Phase 1 checks that wait for a live place"; Experiments phase, "Result: not run yet"); f0148.md Verification log, 2026-11-15.
Evidence: the raft says E6 (the lobby's `UpdateAsync` within `Bests.CHOOSE_WAIT` 5 s, the game place's claim within `Bests.WAIT` 10 s, including inside Roblox's 6 s per-key write window) and E5 (store calls and the attribute in Roblox, the arrows on a phone) "must be run before `./zn ready R0094`", and "If E6 or E5 fails, or the user does not run them when everything else is ready, the lead runs `./zn unfold R0094 f0148`". The raft was readied (f833248ab) with the Experiments phase still reading "Result: not run yet", and f0148's layer was built on it. Its log says only that E5 and E6 "are the human's step" and lists no deviation. The two numbers those experiments test (WAIT 10, CHOOSE_WAIT 5) are pinned by the sequestered `adapters.spec`, so if E6 fails the fallback is a re-prep, not an edit. That would hold back all four layers, since the raft lands as one PR.
Critique: everything the stubs can prove is proven (AC4 passes, and my two adapter mutants were killed), but the one behaviour the design calls unproven, two places writing one DataStore key seconds apart, is now on the way to `main` without the check the raft required and without a recorded decision to skip it. The obvious fix is to append "not run, accepted" to the raft. That is a scope and risk decision for the user, not for the executor.
Consequences: if the user runs E6 now and it fails, f0148 has to be unfolded from a raft whose four layers are already stacked. f0148 is the top layer, so f0143, f0147 and f0158 can still land without it, but that needs a restack and a new final review. If the user accepts merging without E5 and E6, the late-write trade in game-design.md and the "level 1 after 10 s" fallback become live behaviour with no measurement behind them.
Recommendation: escalate to the user before the PR leaves draft, with three options. (a) Run E6 and E5 in Studio with API access on, on this branch's built places (the code is here now, so the prototype patch is no longer needed), and record date, result and pass/fail under the raft's `## Experiments phase`. (b) The user decides to merge without them, recorded as a `Decided with the user (date)` line in R0094.md, and the raft's Exit criteria list the DataStore timing as an unpinned claim beside the two already there. (c) Unfold f0148, as the raft's own rule says. In every case, f0148's Verification log should list this as a deviation with its reason rather than "none".

### F2 [low] The game place's `Bests.reached` reopens the DataStore on every step of every session before it looks at the events
Where: `pickman/src/server/Bests.luau:406-423` (with `open`, 361-369), called through `Sessions.listen` for every step of every live and parked session (`pickman/src/server/Sessions.luau:97-99, 109-112`).
Evidence: `Bests.reached` calls `open()` first and returns when it is nil. `open()` retries `pcall(DataStoreService.GetDataStore)` whenever `store` is still nil. So in a place that cannot reach DataStores (the case the design names: "a place that cannot reach DataStores still boots"), every step of every session, 15 a second each, makes another failing engine call. A step with no `Ready reason = "level"` event, which is almost every step, never needed the store.
Critique: this costs nothing in production, where the first open succeeds and is kept. It is an avoidable per-step engine call wherever opening fails (Studio without API access, a Beta outage). The tempting fix is to cache the failure. That would also turn a transient open failure into "never raise the best for this server's lifetime".
Consequences: opening lazily only when a level event is present keeps one retry per level reached (minutes apart). That matches the design's "opened on first use inside a pcall" and keeps `adapters.spec`'s cases as they are (they reach the store only through a Ready level event).
Recommendation: in `Bests.reached`, scan the events first and call `open()` only for the first `Ready` with reason `level`. Add a place-tier case under `tests/place/` (not the sequestered adapters.spec) that boots `src/server/Bests.luau` on a stub whose `GetDataStore` counts its calls and fails, steps 100 event lists with no level event, and expects 0 calls, then one call for a list holding a `Ready reason = "level"`.

### F3 [low] HudView's comment puts the picks counter "under the level"; the code and the design put it under the score
Where: `pickman/src/client/HudView.luau:29` (`local picks: TextLabel? = nil -- the level's finished wall picks, under the level (f0147)`).
Evidence: `lay()` places it with `Hud.picksBox(blocks.score)` (line 88), and f0147's Design §9 explicitly rejects "under the level", because the touch radar rises into that row on short screens.
Critique: a reader who trusts the comment and "fixes" the code to match it reintroduces exactly the overlap E7 measured. f0147's hud.spec would catch that (my picks-under-level mutant was killed), but the comment still misleads.
Consequences: none.
Recommendation: make the comment say "under the score (Hud.picksBox), not under the level, where the touch radar rises (f0147)".

### F4 [low] The bonanza's grant spells the wire string as a literal beside the constant it names
Where: `pickman/src/shared/Logic/Session/init.luau:612` (`local kind: Picks.Grant = "bonanza" -- Picks.BONANZA`), with `Picks.BONANZA` used two lines later in the event.
Evidence: the same value is written two ways in one branch: the frame's `boon.kind` uses the literal and `WallPicked.item` uses `Picks.BONANZA`. `Picks.BONANZA` is already typed as the singleton `"bonanza"`, so it is assignable to `Picks.Grant`.
Critique: a later rename of the constant (or a second grant beside it) changes the event and not the frame's banner kind. `Hud.BOON_LABELS` is keyed by the frame's kind, so the banner would go blank while the event still reads correctly.
Consequences: none.
Recommendation: `local kind: Picks.Grant = Picks.BONANZA`. If the type checker refuses it, cast once at the constant's definition in Picks rather than at the use.

## Judged criteria (code mode only)
- f0143: none (its Acceptance criteria list Judged: None).
- f0147: none (Judged: None).
- f0158: none (Judged: None).
- f0148: none (Judged: None).

## Not verified here
- The Observed criteria (f0143 OC1 to OC3, f0147 OC1, f0158 OC1, f0148 OC1) need Studio, a phone and a controller.
- f0148's E5 and E6 (F1).
- The raft's two unpinned claims (a boost on the shipped ramp, the PICKS row against the ring). The first is confirmed by reading (above). The second waits for c0196.

## Lesson candidates (for the lead; this review writes no lesson file)
- z-ready (or zz-execute Phase 1): a raft whose document makes a human-run experiment a precondition of `ready` should not be readied, or executed, while its Experiments phase still says "not run". Why: R0094 was readied and f0148 built with E5 and E6 unrun, and the executor logged no deviation. Check: does every "must be run before `ready`" line in the raft have a dated result, or a `Decided with the user` line waiving it, before the first layer starts?
- zz-arch/pickman-arch (adapters): a per-step listener must not touch the engine (open a store, read a service) until the events show it has work. Why: `Bests.reached` reopened a failing DataStore 15 times a second per session. Check: on a step with no relevant event, does the listener return before any engine call?

Verdict: changes
