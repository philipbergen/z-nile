# Review 004: R0060 (design mode)
Inputs: main 9ce6603 plus the uncommitted prep: `tracker/rafts/R0060/{R0060-raft-browser.md,check.sh,design-review-00{1,2,3}.md,design-refute-00{1,2,3}.md}`, `tracker/issues/c0400/{c0400-raft-browser.md,check.sh,acceptance/*.spec.luau}`; existing `scripts/tracker/{main,store}.luau`, `scripts/tracker.sh`, `scripts/lib/graph.luau`, `tests/meta/architecture.spec.luau`, `SETUP.md`, the tracker, testing and architecture skills. This is an extra round that the user approved.

I probed in a detached worktree at `/tmp/r0060-review4` (HEAD 9ce6603, since removed), with the current prep copied in and the author's prototype (`board.luau`, `board.html`, `scripts/vendor/`, the `main.luau` diff) applied. The prep's five specs are byte-identical to the ones the prototype was run against. Results:
- **Promotion without the implementation**: the five specs copied to `tests/acceptance/c0400/`, `board.luau` absent. `tests/meta/architecture.spec.luau` fails only "every require resolves", with exactly five lines, all `require("@scripts/tracker/board")`.
- **Promotion with the prototype**: meta passes (9/0), and the promoted specs pass (28/0).
- **`scripts/tracker.sh promote-check R0060`**: OK, including `luau-lsp analyze tests`.
- **`bash tracker/rafts/R0060/check.sh`**: promote-check, RC1 and AC1–AC4 and AC6 pass. RC0's gate and AC5 fail only on work the prototype hasn't done: `main.luau`'s require order under stylua, and the missing skill line.
- **Lint and format**: stylua `--check` and selene are clean on the acceptance specs.
- **Parent directories**: none of them has a `package.json`, so the harness's `module[...]` loader runs as CommonJS.

Dropped from review-003: F1, F2, F3. Details:
- **F1**: the harness loads modules with `module["req" + "uire"]`, and promotion plus meta passes as above.
- **F2**: the walk now presses ↑ on Waiting's first of two rows, and a wrapping ↑ would show the No raft pane, which lacks "Epsilon".
- **F3**: the E3 wording and the reachability sentence are fixed. One count is left over in the raft doc; see F3 below.

### F1 [medium] Nothing checks the pane's dependency sections or its id links, although "reverse dependencies" is one of the user's explicit requirements and cheap proxies exist
Where: c0400 Problem ("A **detail pane** … its **reverse dependencies**"); Design, "Pane" (Waiting for, Depends on, Dependents; "Clicking any id link shows that item as a search would") and "DOM subset" ("The smoke test doesn't click them (OC1 covers them)"); `smoke.spec.luau` HARNESS (`closest: () => null`); OC1 step 2.
Evidence: model.spec proves the *data* (`R0020.dependents == {R0030}` and so on), but no Checked criterion looks at how the page renders it.
- **Mutant 1**: I deleted the three lines that emit "Waiting for", "Depends on" and "Dependents" from the prototype's `board.html`. smoke.spec and page.spec still pass (11/0).
- **Mutant 2**: I removed the pane's click handler body, so id links do nothing. smoke.spec still passes (4/0).
- **Effect**: a page that never shows reverse dependencies, or whose links are dead, passes RC0 and AC1–AC6. Only a human doing OC1 step 2 would catch it.
- **Why it matters**: those links are how blocked waiting rafts are reached from the list at all (Design, "Tabs": "reachable through their blockers' Dependents … or Waiting-for links"). So a dead link hides every non-top-level raft from list navigation.
- **Cheap proxy**: both behaviours can be measured in the existing harness. On the walk fixture, Beta's pane must show Depends on R0010 and Dependents R0030, and Gamma's pane must show Waiting for R0020. Nothing else in those panes mentions R0030.
Fix:
- **Pin the link markup** in the Design, as the prototype already has it: `<a class="jump" data-id="ID">`.
- **Make clicks work in the harness**: give the fake element a `getAttribute`, and let a click target's `closest("a.jump")` return itself.
- **Extend the walk**: while Beta is shown, expect `/Dependents[\s\S]*R0030/` and `/Depends on[\s\S]*R0010/`. After the `F0031` search, expect `/Waiting for[\s\S]*R0020/`. Then dispatch a click on the pane with a target `{ closest: () => ({ getAttribute: () => "R0020" }) }`, and expect `/Beta/.test(pane())`.
- **Update the docs**: add "the pane lists Waiting for, Depends on and Dependents, and an id link jumps there" to AC6, and trim OC1 step 2 to layout.

### F2 [low] "↑ from an unlisted pane selects the last row" is designed but untested, and the prep prototype does the opposite
Where: c0400 Design, "Keys" ("When the pane shows an entry that isn't in the list … ↓ selects the first row and ↑ the last"); AC6 names only "↓ from an unlisted pane selects the first row"; `smoke.spec.luau` walk.
Evidence:
- **The prototype**: `go()` sets `sel = -1` for an unlisted entry, and ↑ calls `select(sel - 1)`, which is `select(-2)`. That clamps to row 0, the *first* row.
- **The spec**: it never presses ↑ from an unlisted pane.
- **Effect**: an executor who follows the prototype pattern ships behaviour that contradicts the design, and every check passes.
Fix: either drop the "↑ the last" clause from the design, or add it to the walk. After the `F0031` search (Gamma shown, list on Waiting), press ArrowUp and expect `/f0060/.test(pane()) && /No raft/.test(pane())`. Then re-run the search before the existing ArrowDown step.

### F3 [low] A stale case count is left in the raft doc, and an untested detail in the page design
Where: R0060 "Experiments phase", E3 ("five acceptance specs (27 cases)"); c0400 Design, "Search" ("Successful jumps update `location.hash`").
Evidence:
- **Case count**: c0400's E3 and refute-003 say 28 cases now, and I counted 28 passing on the prototype.
- **`location.hash`**: the design says successful jumps update it, but no check does. The harness records `history.replaceState` into `sandbox.location.hash`, and nothing asserts on it.
Fix:
- **Case count**: change the raft doc to 28.
- **`location.hash`**: optionally, in the walk after the `F0031` search, expect `sandbox.location.hash === "#f0031"`.

Verdict: changes
