# Review 006: d0124 (design mode)
Inputs: prep branch f647ef12 (re-prep: `git diff HEAD~1 -- pickman/.tracker/issues/d0124`), d0124.md, check.sh, acceptance/*.spec.luau, R0044 design-review-001..005 and design-refute-001..005, `pickman/.tracker/rafts/R0044/experiments/prototype.patch`, origin/main 2ec6f836 (an ancestor of f647ef12), lesson pickman-test/stub-loaders-fall-back.

Evidence run in a scratch worktree of f647ef12 (since removed), prototype applied with `git apply --3way --directory=pickman`:
- The patch applies cleanly (all 8 Touched modules). `lune run tests/run -- .tracker/issues/d0124/acceptance/*.spec.luau`: 80 passed, 0 failed, 5 spec files. `./zn check d0124`: 7/7 criteria passed.
- The pre-fix spec (`HEAD~1`) on the prototype: 24 passed, 1 failed, `stub: no module for @game/ReplicatedStorage/Shared/Logic/Pad`, so the fix is needed.
- The FlowView case still pins its name. With FlowView reverted to main's version (no miss/place wiring), it fails. With `rankLabel.Visible = true` (visibility mutant), it fails.
- Adapters loaded by the specs, compared from fa9cc9bc (`src/…`) to HEAD (`pickman/src/…`): HiscoreStore, Ranks, Boards and LobbyView are byte-identical, and so are Logic Hiscores, Flow, Lobby and Travel. Only FlowView changed (f0146: `require(…/Logic/Pad)`, `Pad.CONTINUE` key). The other four specs (top, drivetop, flow, lobby) require only `@logic/*` directly and have no stub loader, so they can't break this way.

Answers to the brief: (1) the fix is correct and minimal, and it still pins the miss line, the place line and visibility. (2) No other spec or loader of d0124 breaks against current main. (3) The patch applies and the design holds, with one finding about the loader's future fragility (F1).

### F1 [medium] adapters.spec's stub `require` is still a closed table, so the next require added to any of the five adapters it loads turns all 25 cases red again
Where: `pickman/.tracker/issues/d0124/acceptance/adapters.spec.luau`, `env` → `require` (`assert(found ~= nil, \`stub: no module for {spec}\`)`, ~line 165), and the fix at line 814.
Evidence: on the prototype, I put one correct, unused line `local _M = require("@game/ReplicatedStorage/Shared/Logic/Maze")` at the top of HiscoreStore, Ranks, FlowView, Boards and LobbyView. adapters.spec then gave **0 passed, 25 failed**. With the same edits and a fallback loader (below), even the pre-fix spec without the `Pad` entry gave 25 passed, 0 failed. The re-prep hit exactly this failure and fixed only the instance: it added `Pad` to one table. f0145 (prep-paid-play-and-continues, `depends_on` d0124) touches `src/server/HiscoreStore.luau` after d0124 lands. By then this spec is promoted to `tests/acceptance/d0124/` and can't be edited during f0145's execution, so any require it adds there stops f0145 the same way R0044 was stopped.
Critique: this repeats the existing lesson word for word. Its How to apply says "in a new stub loader, fall back to the real Logic module (`@logic/<name>`) for any Logic require not stubbed, rather than asserting". The re-prep's own Verification-log line proposes "Lesson candidate: pickman-test/stub-loaders-fall-back" as if it were new. The tempting fix is to add more entries (for example every Logic module) to each `env(...)` call. That still breaks on the next new Logic module.
Consequences: a Logic fallback loads real pure modules where a test might have wanted a stand-in. That's harmless here, because every case already passes the real Logic module and stubs only siblings (`./HiscoreStore`) and services. Siblings and services must keep failing loudly: a fallback for them would hide a missing stand-in. The `Pad` entry becomes redundant, but it can stay.
Recommendation: in `env`'s `require`, when `modules[spec]` is nil and `spec` starts with `LOGIC`, return `(require :: any)("@logic/" .. string.sub(spec, #LOGIC + 1))`. Keep the assert for every other spec. Precedents: `tests/acceptance/f0126/views.spec.luau:209` and `tests/acceptance/f0146/controls.spec.luau:72`. Verified above: 25/25 pass with the fallback, with or without `Pad` in the table, and with an extra Logic require in all five adapters. Record the extra-require edit as a correct variant that must stay green in the Rules and mutants record. Re-run the FlowView-revert and visibility mutants to confirm the case still kills them.
Lesson: pickman-test/stub-loaders-fall-back

### F2 [low] The Verification log calls an existing lesson a "candidate"
Where: d0124.md, Verification log, 2026-11-01 line, "Lesson candidate: pickman-test/stub-loaders-fall-back".
Evidence: `pickman/skills/pickman-test/lessons/stub-loaders-fall-back.md` has existed since 5f4aa300 (f0126's prep) and already names this failure.
Critique: the harvest will write a duplicate file, or drop the candidate as if it were already handled, when the real lesson is that the prep didn't apply it.
Consequences: none.
Recommendation: replace the line with a harvest note that appends to the existing lesson: `- note d0124 re-prep: FlowView gained a Logic require (f0146) and the closed loader failed; pickman-test/stub-loaders-fall-back`. Add a short paragraph to the lesson about this repeat. Write no new lesson file.

Verdict: changes
