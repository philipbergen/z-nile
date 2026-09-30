# Review 003: R0060 (design mode)
Inputs: main 9ce6603 plus the uncommitted prep: `tracker/rafts/R0060/{R0060-raft-browser.md,check.sh,design-review-00{1,2}.md,design-refute-00{1,2}.md}`, `tracker/issues/c0400/{c0400-raft-browser.md,check.sh,acceptance/*.spec.luau}`; existing `scripts/tracker/{main,store}.luau`, `scripts/lib/graph.luau`, `tests/meta/architecture.spec.luau`, `tests/run.luau`, `.luaurc`, `.gitignore`, the testing skill. Probed in a detached worktree at `/tmp/r0060-review3` (since removed): the five acceptance specs copied to `tests/acceptance/c0400/` as `tracker.sh done` would place them, with a stub `scripts/tracker/board.luau`, then `lune run tests/run -- tests/meta/architecture.spec.luau`. Also checked the marked 18.0.14 tarball (sha256 matches the pin; it has no `id="…"` text that could confuse the harness's load-order index), and how Lune's `process.exec` fails when the binary is missing (it raises, so the smoke spec's `pcall` gives its clear message).
Dropped from review-002: F1, F2, F4, F5, F6, and F3 except the ↑ clamp (each fix is in the documents and specs as refute-002 says: the harness models load order and fires `DOMContentLoaded`; model.spec and the `quiet` run cover a tree with nothing active; the walk presses ←, `/` with `preventDefault`, keys in search, Esc, ↓ from an unlisted pane and checks that the list switches tab; SETUP.md is in Touched modules; No raft entries carry `dependents`, asserted as `{ "R0070" }`; OC1, the spec count and the `Issue` type are corrected). The ↑ clamp is repeated below as F2.

### F1 [high] Once promoted, smoke.spec's HARNESS string contains `require("fs")` and `require("vm")`, which break tests/meta: RC0's `promote-check` fails and `tracker.sh done` rolls back, and the executor can't fix it because the spec is sequestered
Where: `tracker/issues/c0400/acceptance/smoke.spec.luau`, first line of `HARNESS` (`const fs = require("fs"), vm = require("vm");`); `scripts/lib/graph.luau` (`stripComments` copies long strings `[==[ … ]==]` verbatim, then `graph.build` scans them with `REQUIRE_PATTERN`); `tests/meta/architecture.spec.luau` "every require resolves"; R0060 `check.sh` RC0 `promote-check`; the testing skill ("Never write literal `require("…")` text inside strings or comments. The graph scanner would treat it as a real require. Build such text by concatenation.")
Evidence: I copied the five specs into `tests/acceptance/c0400/` in a scratch worktree, as `done` places them, and ran the meta spec:
```
FAIL tests/meta/architecture.spec.luau :: every require resolves
  expected "", got "tests/acceptance/c0400/smoke.spec.luau: require(\"fs\")
tests/acceptance/c0400/smoke.spec.luau: require(\"vm\")"
```
The prep never showed this: while the spec is under `tracker/`, neither `graph.build({ "src", "tests" })` nor c0400's `check.sh` scans it, so AC1–AC6 all pass and E3/E4 report PASS. But `promote-check` runs meta over the promoted copies, so R0060's `check.sh` fails at RC0, and `done` would roll back. Specs are sequestered, so the executor can only stop and escalate. The raft can't be finished as prepped.
Fix: In HARNESS, build the JS require so it doesn't match `require%(%s*["']`, for example `const fs = require ("fs"), vm = require ("vm");` (a space before `(`, which JS accepts), or splice the string in Luau (`"const fs = req" .. "uire(\"fs\")…"`) as the testing skill says. Then re-run the scratch promotion and meta (or `tracker.sh promote-check R0060` with a prototype `board.luau`) and record that it passes. Add "promote-check passes on the prototype" to E3/E4.

### F2 [medium] ↑ clamping at the first row is still only tried on a one-row list, so a wrapping ↑ passes AC6 (repeat of review-002 F3)
Where: `smoke.spec.luau` walk (`key("ArrowUp"); expect(/Beta/.test(pane()), "ArrowUp stops at the first row")`); c0400 AC6 ("↓/↑ move the selection, clamped"); refute-002 F3 ("↑ at the top")
Evidence: The walk presses ↑ first on the Active tab, which in the smoke fixture holds only R0020 (f0020 has a raft, so there's no `none:active`). On a one-row list, wrapping and clamping land on the same row, so a page where ↑ from row 0 goes to the last row passes that check. No other ↑ in the walk starts from row 0 of a longer list: the next ↑ goes from row 1 of Waiting. ↓ clamping is tested properly, on Waiting's two rows.
Fix: After "ArrowRight moves to Waiting" (Epsilon selected, row 0 of 2), press ArrowUp and expect `/Epsilon/.test(pane())` and `!/No raft/.test(pane())`, before the ArrowDown steps.

### F3 [low] Stale or overbroad statements in c0400's Design
Where: c0400 "Unknowns & experiments" E3; Design "Tabs", last bullet
Evidence:
- E3's first line still says the prototype "passes all four acceptance specs (21 cases)". The next bullet says five specs and 27 cases.
- "Blocked waiting rafts, including rafts that block each other, are reachable through their blockers' Dependents … or Waiting-for links". Two waiting rafts that block only each other have no top-level ancestor, so no list row leads to either of them. They're reachable only by search, which the sentence does also name.
Fix: Delete the "four … (21 cases)" wording from E3. Say that mutually blocking rafts are reachable only through search, and through each other's links once one of them is shown.

Verdict: changes
