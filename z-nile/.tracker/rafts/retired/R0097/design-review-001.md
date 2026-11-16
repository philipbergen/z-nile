# Review 001: R0097 (raft mode)
Inputs: raft-stack-dependencies at e0496e5e6 (R0097 files as of 88a54fb3d): R0097.md, R0097/check.sh; c0189.md, c0189/check.sh, c0189/acceptance/{wiring,hooks-command,hooks-plan,repo-hook,replace-mode}.spec.luau, c0189/experiments/prototype.patch; c0123.md, c0123/check.sh, c0123/acceptance/{entries,wording,launchers}.spec.luau, c0123/experiments/prototype.patch; retired R0098.md; R0070.md and c0194.md (step 8); R0072.md and c0193/acceptance/docs.spec.luau; R0068.md and c0122.md; z-nile/engine/main.luau (`done`, about line 5047); z-nile/tests/lib/{engine,trackerfix}.luau; z-raft and z-design lessons.
Grouped: [c0123@d08f1e683355, c0189@92eb2ee3fbdd]

Raft mode. These findings are about the stacking: the raft and the three cross-raft interfaces. What checked out: every quoted user decision in the Theme is found by `git grep -F` in the member's own document. The Order follows `depends_on`. The chain R0078 → R0070 → R0097 matches `./zn find` (R0070 and R0078 are active). c0193's loop lint reads `.luau` files only, so `cleanenv.sh`'s shell loops are outside it. `c0055/setup-run` is a promoted spec, which both layers may override. The members' other surfaces are text neighbours.

The main defect is that the stacking copied both designs' agreement about the hook's first line. That agreement was written for two rafts, landing one after the other. In one raft, the member specs that pin that line are still sequestered. F1 to F3 cannot be fixed at raft level: each needs a member's design to change.

### F1 [high] c0189's sequestered `wiring.spec` pins the hook's first line as `#!/bin/sh`, and c0123's `entries.spec` requires `#!/bin/sh -p` on the same file, so one of them is red at RC0 whatever the line says
Where: R0097.md, Whole-raft design, "`z-nile/lib/repo-hooks/reference-transaction` and `c0189/wiring.spec`" ("Agree: the two say the same thing. This raft changes the pin in c0123's layer") and "**Conflicts**: none found"; c0189/acceptance/wiring.spec.luau:204; c0123/acceptance/entries.spec.luau:36-46 and the case "every tracked script a caller can start is privileged"; c0123.md Regression guard (`Overrides: … c0189/wiring`); c0189.md:133.
Evidence: wiring.spec:204 says `t.expect(string.sub(hook, 1, 10)).toBe("#!/bin/sh\n")`. c0189/check.sh AC4 runs it from `$HERE/acceptance`, the issue folder, until `done` promotes it. entries.spec runs `git grep -nI -e '^#!'` over the real tree and wants `#!/bin/sh -p` for every path under `^z-nile/lib/repo-hooks/`. On `#!/bin/sh` it fails with `z-nile/lib/repo-hooks/reference-transaction: #!/bin/sh`, which is exactly what c0123's E24 recorded. `./zn done` runs `runCheck(raft)` before it promotes anything (main.luau, "check.sh failed; not done", then the promotion loop). The raft's check.sh runs every member's check.sh on the final tree. So the final tree fails c0189 AC4 if the line is `#!/bin/sh -p`, and fails c0123 AC5 if it is `#!/bin/sh`.

Both designs wrote their agreement for separate rafts:
- c0189.md:133: "it overrides `wiring.spec`'s first-line pin in its own raft".
- c0123.md:210: "this chore changes them in its own raft".
- The retired R0098: "c0189 lands first".

An `Overrides:` line can name promoted specs only (lesson z-design/bottom-layer-pins-only-what-upper-layers-keep: "an `Overrides:` line names promoted specs only, not the raft's own sequestered ones"). In one raft, c0189's `wiring.spec` is still in `issues/active/c0189/acceptance/`. "During execution they must not change" (zz-test, Sequestered). Phase 3 step 4's sequestration check lists any change there that is not an `R100` rename, and zz-review code-mode item 2 makes that a high finding.
Critique: An executor who follows "This raft changes the pin in c0123's layer" edits another member's sequestered acceptance spec. The tempting raft-level ways out each leave a member red:
- keep the hook on `#!/bin/sh`: c0123 AC5 fails.
- let c0189's layer ship `-p`: c0189 AC4 fails, against its design ("The hook's first line stays `#!/bin/sh` here").
Consequences: Every fix changes a member's contract:
- c0189's first line and its pin;
- c0123's Overrides line, its Touched `z-nile/lib/repo-hooks` and `z-nile/tests/acceptance/c0189`, and its Implementation step 1.

So z-raft takes the members out (`./zn unfold`), and each goes back to z-design for a round. Folding them again is a new record that needs its own coherence review, which takes two landings (lesson z-raft/rafted-member-changes-stay-in-the-raft). Undoing the stacking instead would reverse the user's ruling of 2026-11-15 ("Yes, one raft (Recommended)").
Recommendation: Keep the user's one-raft decision. Unfold c0189 and c0123 and send both back to z-design:
- **c0189's re-prep** ships the hook as `#!/bin/sh -p` from its own layer, with the pin `t.expect(string.sub(hook, 1, 13)).toBe("#!/bin/sh -p\n")`. It says why: c0123's rule, and macOS `/bin/sh` imports an exported function into a plain `#!/bin/sh` script (c0123 E13). E24 already ran `repo-hook.spec` 16 of 16 with the `-p` line.
- **c0123's re-prep** drops:
  - `c0189/wiring` from Overrides;
  - `z-nile/lib/repo-hooks` and `z-nile/tests/acceptance/c0189` from Touched;
  - the two "not in the patch" edits from Implementation step 1;
  - the PR sentence that "every installed copy was out of date" (F7).

  Its `entries.spec` stays as it is.
- **Then** fold both again after R0070 is done (F4), with a new coherence review whose inputs include the stacked run of F5.

Spec cases for the merged tree:
- `wiring.spec` with the `-p` pin passes on c0189's layer alone and on c0123's.
- A mutant that drops `-p` from the hook fails both `wiring` and `entries`.

If the user would rather undo the stacking (c0123 in a raft of its own behind R0097), the designs can stay as they are for F1 and F2. That reverses their 2026-11-15 ruling and brings back the wait it removed, so offer it to them as the alternative, not as the default.
Lesson: z-design/bottom-layer-pins-only-what-upper-layers-keep

### F2 [high] c0123's check.sh AC6 runs `tests/acceptance/c0189/wiring.spec.luau`, a file that exists only after `./zn done` promotes c0189, so in one raft c0123's layer cannot pass `./zn check c0123` and RC0 is red
Where: c0123/check.sh, the `C189=c0189; AC6+=("tests/acceptance/$C189/wiring.spec.luau")` lines; c0123.md AC6 ("c0189's wiring spec is listed, so AC6 is red in a tree without c0189"); R0097.md Theme ("so it is a later layer in c0189's raft") and Exit criteria.
Evidence: The check.sh comment says it: "c0189 is a dependency: its wiring spec must exist when this runs, so it fails loudly if it does not." Run in this worktree: `./zn run --time 90 -- bash -c 'cd z-nile && lune run tests/run -- tests/acceptance/c0189/wiring.spec.luau'` printed `FAIL tests/acceptance/c0189/wiring.spec.luau: could not load spec: … could not resolve child component "c0189"` and `0 passed, 1 failed`, exit 1. In this raft c0189 is promoted only inside `./zn done R0097`, after `runCheck(raft)`. zz-execute Phase 2 step 4 needs `./zn check c0123` to show every AC as PASS before `./zn finish c0123`, so the top layer cannot finish, and RC0 fails on the same line. This holds even when F1 is fixed.
Critique: The executor will be tempted to copy `wiring.spec` into `z-nile/tests/acceptance/c0189/`. That duplicates a sequestered spec, and promotion then meets a file already in place. The other temptation is to edit c0123's sequestered check.sh, which is a breach.
Consequences: check.sh is part of c0123's contract, so the fix is c0123's re-prep (F1's unfold). Whatever replaces the line must still pass when RC0 runs before promotion, and again after it.
Recommendation: In c0123's re-prep, remove `c0189/wiring` from AC6 and the AC6 text ("33 files"). c0189's own check.sh AC4 runs `wiring.spec` in the same RC0, so nothing goes unchecked. If c0123 must still name it, resolve it the way `A=` resolves its own specs (the issue folder from `./zn find c0189`, else the promoted path). AC6's other dependency paths (`c0194/{callers,runner,shim}`) are fine, because R0070 lands before this raft. Spec cases: `./zn check c0123` passes on the c0123 layer while c0189 is not yet promoted, and `bash $(./zn find R0097)/check.sh` passes on the final tree.
Lesson: z-design/bottom-layer-pins-only-what-upper-layers-keep

### F3 [high] c0123's sequestered `wording.spec` pins zz-arch's rule 9 as "Launchers start children…", but R0072's c0193 (active) pins rule 9 as "Every scanning loop advances…"; the raft says the two "do not meet"
Where: R0097.md, Interfaces with other rafts, "**Beside R0072 (c0193)**: both edit `z-nile/skills/zz-arch/SKILL.md` and `z-nile/skills/zz-test/SKILL.md`, in different passages that do not meet"; Whole-raft design, the skills paragraph ("Agree: different bullets and rows"); c0123/acceptance/wording.spec.luau:99; `issues/active/c0193/acceptance/docs.spec.luau:32,39`.
Evidence: The two pins:
- wording.spec: `lineStarting(arch, "9. **Launchers start children in the allow-listed environment**")` (c0123's patch adds `+9. **Launchers …` at prototype.patch:1325).
- c0193's docs.spec: `has(s, "9. **Every scanning loop advances on every pass, or fails closed.**")` and `has(s, "the ninth by \`z-nile/tests/acceptance/c0193/tree.spec.luau\`")`.

zz-arch has rules 1 to 8 today. R0072 is active (`active-raging-badger-crimson`). R0097 waits for R0070, and R0070 waits for R0078, so R0072 will almost certainly land first and its `docs.spec` will be promoted. c0123's layer then has two choices, both wrong:
- renumber the scanning-loops rule to 10: c0193's promoted spec fails, and that override is not in c0123's Overrides line.
- number both rules 9: both specs pass and zz-arch carries a malformed list.

If R0097 landed first, c0193's sequestered spec is the one that could not pass. A second, smaller miss in the same file: c0189 and c0123 both rewrite zz-arch's `z-nile/lib/` layout row (c0189 prototype.patch:571, c0123 prototype.patch:1317). That is a text conflict only, because both pin substrings, but it is not "different rows".
Critique: The easy way out, two lines that start `9.`, is a wrong implementation that passes every check. A renumbering instead overrides another raft's promoted spec without declaring it.
Consequences: The fix changes c0123's sequestered `wording.spec`, which is a member design change: it rides on F1's unfold of c0123. The new pin must hold in either landing order.
Recommendation: In c0123's re-prep, pin the rule by its text, not its number: a line matching `^%d+%. %*%*Launchers start children in the allow-listed environment%*%*`, with the same two needles. Add the rule after whatever rule is last on `main` (10 once R0072 is done). Write the interface in R0097.md and R0072.md alike (lesson z-raft/cross-raft-order-written-in-both): "the second lander takes the next rule number; neither renumbers the other's rule". Also correct the row sentence: both layers edit zz-arch's `z-nile/lib/` row, and the second keeps both phrases (`repo-hooks/ …` and `cleanenv.* …`). Spec cases: `wording` passes with the rule numbered 9 or 10 and fails when the rule is missing or its two needles are gone; c0193's `docs.spec` passes on the merged tree.
Lesson: z-design/quote-other-preps-before-promising

### F4 [medium] When R0070 lands, its step 8 adds a note to c0189.md, so R0097's `grouped:` hash for c0189 goes stale and `./zn ready R0097` refuses; c0189's own design says to raft it only after R0070 is done
Where: R0097.md Cross-raft waits; c0189.md:132; c0194.md:352 (Implementation step 8).
Evidence: c0189.md:132: "R0070's step 8 adds a dated note under this document … Because it edits this document, **this chore is rafted only after R0070 is done**: a raft that grouped it earlier would hold a stale `grouped:` hash and `./zn ready` would refuse it". c0194.md's step 8: "and the dated notes under c0189.md and c0157.md". R0070 is active, and c0189.md on `origin/main` has no note yet (`git diff HEAD origin/main -- z-nile/.tracker/issues/c0189` is empty). This raft has just recorded `c0189@92eb2ee3fbdd`. z-raft §5, Redesigned members: "`./zn ready` refuses the landed raft the same way". The Cross-raft waits section says only "this raft is readied only after R0070 is done".
Critique: The lead finds this at `ready`. Two steps follow that no document names: fold again (a new record), then a new coherence review (lesson z-raft/member-handshakes-reach-the-order).
Consequences: F1 to F3 need an unfold and a re-fold anyway. A re-fold before R0070 lands goes stale again, so the re-fold must wait for R0070.
Recommendation: Add to Cross-raft waits: "R0070's `done` adds a dated note to c0189.md (c0194 step 8), which stales this raft's `grouped:` record for c0189. Fold c0189 again after R0070 is done, and run the coherence review on that record. `./zn ready R0097` refuses until then." Time the re-fold after F1 to F3's re-preps and after R0070, so one new record and one review cover both.

### F5 [medium] Neither member's whole acceptance set has run on a tree with both prototypes applied in the raft's order; the raft leaves four specs to the executor, and a run of the two check.sh files would have shown F1 and F2
Where: R0097.md Experiments phase ("No merged run of the two designs with `setup-run` has been done …; the c0123 layer's executor does it"); Whole-raft design (the executor "reruns `setup-run`, `entries`, `repo-hook` and `wiring`"); c0123.md E24.
Evidence: E24 applied the prototypes as c0194, then c0123, then c0189, the reverse of this raft's Order. It ran `entries`, `repo-hook` and `wiring` only, and `wiring` was red on the pin. None of these has run on a stacked tree:
- c0189's `hooks-command.spec`, 20 cases. Each runs `bash zn hooks` in a `trackerfix` copy. After c0123, that goes through the cleanenv prologue with `GIT_CONFIG_GLOBAL` pinned to the account's file, while the spec reads `git config --show-scope` output.
- c0189's `hooks-plan` and `replace-mode`.
- c0123's `inherited-hooks`, `cleanenv`, `launchers` and `wording`.
- either member's `check.sh`.
Critique: A red case found during execution sits in a sequestered file the executor may not touch. That is a stop and an escalation, which is what the rafting is meant to prevent.
Consequences: The run needs c0194's prototype under it (R0070 is not done), a scratch clone under `.cache/.tmp/` and `./zn run`. Each red case must be an Override of a promoted spec or a named interface.
Recommendation: Before the re-fold, make a scratch clone under the main checkout's `.cache/.tmp/` (`origin` removed, an ordinary identity). Apply c0194's, then c0189's (re-prepped), then c0123's (re-prepped) prototype, in the raft's Order. Run `bash z-nile/.tracker/issues/c0189/check.sh` and `bash z-nile/.tracker/issues/c0123/check.sh` in full, plus `c0055/setup-run`, each through `./zn run --time …`. Record the result in the raft's Experiments phase, with every red case named as an Override or an interface.
Lesson: z-raft/run-sequestered-specs-on-all-prototypes-together

### F6 [low] Interfaces with other rafts omits R0068 (c0122, active), which edits the same zz-test Ref guard line, `fence.sh`'s header and `repo-fence.spec`'s allow-list as c0123
Where: R0097.md, Interfaces with other rafts (lists R0070, R0072, R0077).
Evidence: c0123.md:83 says c0122 edits "the same bullet and header … whichever lands second resolves a text conflict". c0122.md:99 says the same of c0123, and its step 5 runs `tests/acceptance/c0123/wording.spec.luau` if it is promoted. R0068.md:52 names c0123. c0122 is `active-badger-quiet-violet` in R0068.
Critique: The R0097 executor reads the raft for the other rafts it meets. The rule is in both member designs, so this is only an omission.
Consequences: none.
Recommendation: Add a "**Beside R0068 (c0122)**" bullet that quotes the members' rule: the second lander keeps both issues' sentences on zz-test's Ref guard line, and the two allow-list blocks in `repo-fence.spec` go one after the other.

### F7 [low] Four statements copied from c0123's former raft are false in the stacked raft: the stale-installed-hook Risk, its PR sentence, the rollback line and the spec that holds the launcher scan
Where: R0097.md Risks ("A stale installed hook after c0123's layer", the Rollback bullet); Whole-raft design ("c0123's launcher scan over c0189's code: `launchers.spec` …").
Evidence:
- **Stale hook.** In one raft no copy is installed before the merge. c0189's step 3 says "Do not run `./zn hooks` in this worktree", `origin/main` has no hook until R0097 lands, and step 9 installs the merged text the first time. The `#!/bin/sh` text never reaches `main`'s first-parent history.
- **Rollback.** After c0123's layer is reverted by hand, the installed `-p` copy is a text `main` held, so `--check` passes it with a note (`hooks.plan`'s `older`). Rerunning `./zn hooks` is optional, not needed.
- **Launcher scan.** The scan is `entries.spec`'s case "every Lune launcher starts its shells as `/bin/bash -p` or `/bin/sh -p`" (its `LAUNCHERS` include `main.luau` and `sh.luau`). E24 ran it 4 of 4 on a tree with c0189's code, so it was run, not only reasoned ("By the designs' reading").
Critique: The PR would tell every session its installed copy is stale when it has none.
Consequences: With F1's recommendation (c0189 ships `-p`), only c0189's step-9 notice remains.
Recommendation: Replace that Risk with c0189's step-9 notice: run one `./zn hooks` after the merge, and every gate's hooks stage reports "missing" until then. Drop the PR sentence (c0123's re-prep drops it from its step 1, F1). Correct the rollback line and the spec name.

Verdict: changes
