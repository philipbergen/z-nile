# Review 002: R0099 (design mode, raft)
Inputs: branch `raft-provenance` at f7048f2a (`z-nile/.tracker/rafts/R0099/R0099.md`, `check.sh`, `design-review-001.md`, `design-refute-001.md`, `harvest.md`); the five member folders (documents, `check.sh`, `acceptance/`); the prototype stack `.worktree/proto-provenance-stack` at b4a35628 (`z-nile/engine/provenance.luau`, `publish.luau`, `main.luau`, `who.luau`, `board.html`, `tests/lib/fixture.luau`); `origin/proto-c0263-raft`; origin/main c2833872 (`z-nile/.tracker/rafts/active/R0100/R0100.md`, `d0298.md`, `active/c0306/c0306.md`, `z-nile/tests/acceptance/c0264/intent.spec.luau`); `.worktree/proto-heartbeat-stack` e087da65, `.worktree/proto-d0298` 54a74264, `.worktree/proto-c0306`; `z-nile/engine/main.luau` (`cmd.done`), `paths.luau` (`paths.rewrite`), `raftplan.luau` (`recordHash`), `z-nile/tests/run.luau`. Probes ran through `./zn run --time`, from scratch files in this worktree's `.cache/rv99-002/` (`hash.luau`, `regs.luau`, `rc1.sh` and the RC1 fixture); they are left there so the author can rerun them.
Grouped: [c0263@1b93fc9d0c76, c0280@9db248601f55, c0282@c7064c6ab955, c0283@c941fa9321b7, c0284@27c0dce08c9e]

What holds:
- **The record.** I recomputed each member's hash with `raftplan.recordHash` over its tracked folder (`.cache/rv99-002/hash.luau`), and all five match `grouped:`.
- **The Order.** It follows every `depends_on`: c0283 [c0263], c0284 [c0263, c0280], c0282 [c0263]. `./zn stack R0099` prints c0263, c0280, c0283, c0284, c0282. No earlier layer's sequestered spec reads a later layer's code. I grepped every spec of c0263, c0280, c0283 and c0284 for c0282's names (`ENV_VARS`, `AGENT_MARKERS`, `raftDetail`, `via`, `raftedProblem`, `ZN_VIA`, `lifecycle`) and for the lifecycle commands (`fold`, `new raft`, `recombine`, `status`, `done`). None of them uses those names or drives those commands. c0283's and c0284's specs write their record rows by hand. On the stack, the only reader of `AGENT_MARKERS` is c0282's own `lifecycle.actor` (main.luau:390), so the alias and its reader arrive in the same layer. c0282's `provenance.spec` pins `#provenance.AGENT_MARKERS == 5`, and c0283's `AGENT_VARS` has five entries.
- **The publish rule (item a).** It matches c0263's contract and the raft's paragraph. On the stack, `publish.luau:466-488` runs c0263's `publishProblem(existing, new, pid, allowed)` first. It consults `approvedPublishProblem(existing, new, pid, buildRead(approval.md), <that commit's approval.md>)` only when that rule refuses, the path is not `/active/`, and the same commit carries the same folder's `approval.md`. `/done/` is refused before either rule runs, and `PUBLISHED` is unchanged. `approvedPublishProblem` (provenance.luau:142-188) does exactly what Behaviour 4 lists. `approve --publish` (main.luau:5984-6022) builds the record from `show(recordRel)`, which is origin's file, and carries both files in one `tracker: approve <id>` commit.
- **The requires (item a).** The raft states them (Whole-raft design :41 and :43, and E1c), and they are acyclic. `contract.luau` requires only `@lune/serde`. `trail.luau` requires `@lune/process`, `./ids` and `./projects`. None of them requires `provenance`. The modules that require `provenance` are `who`, `dispatcher`, `audit`, `publish`, `main`, `boardprov` and `mergerecords`. zz-arch's one-reader rule holds: `approval.md` is read through `contract.parse` in both places.
- **RC2 and RC4's key check.** RC2 fails on a second literal list and on a `table.clone` copy. RC4's `"provenance"` needle is sound: main's built page contains 0 occurrences, and the stack's `board.html` template has none literally, so the key comes only from the data.
- **The merge with R0100.** R0099's added `main.luau` lines use none of the eleven requires that the heartbeat stack inlines (`gateLib`, `openlist`, `pathsLib`, ...), so merging R0100 is textual, not a name break.

### F1 [high] c0283's AC5 runs c0263's specs at their promoted paths, which do not exist until `./zn done` promotes them, so c0283 cannot finish and R0099 cannot be done
Where: c0283/check.sh:22 (AC5); R0099.md:104-106 (E1c to E1e, "c0283 7/7"), :117 (E4); `cmd.done` (main.luau:5047 vs :5095-5115)
Evidence:
- c0283's re-prep (#353, `git show afb9b4f1 -- …/c0283/check.sh`) added `tests/acceptance/c0263/provenance.spec.luau tests/acceptance/c0263/publish.spec.luau` to AC5's `lune run tests/run -- …` line.
- On this branch, `z-nile/tests/acceptance/` has no `c0263`, and specs are promoted only by `done` (zz-execute: "Don't modify or move them; `done` promotes them").
- I scanned every `tests/…spec.luau` path in the five member check.sh files. These two are the only paths that do not exist.
- From `z-nile/`, `./zn run --time 90 -- lune run tests/run -- tests/acceptance/c0263/provenance.spec.luau tests/acceptance/c0263/publish.spec.luau` prints `FAIL tests/acceptance/c0263/provenance.spec.luau: could not load spec: … could not resolve child component "c0263"` and exits 1.
- `ready`'s `paths.rewrite` rewrites only item paths (`<root>/<issues|rafts>/[active/|done/]<ID>`), so this path survives readying.

Consequences of the missing path:
- At layer 3, `./zn check c0283` fails AC5, and zz-execute step 4 finishes an issue only when "`./zn check <issue>` shows every AC as PASS". `./zn start` then cannot open c0284 or c0282.
- If AC5 were somehow skipped, `done` still runs `runCheck(raft)` (main.luau:5047, `fail("… check.sh failed; not done")`) before the merge and the promotion. RC0 runs c0283's check.sh there, so `done` fails too.

Why the prototype passed: `proto-provenance-stack` holds promoted copies beside the sequestered folders (`z-nile/tests/acceptance/c0263/`, and the same for c0280, c0282, c0283 and c0284). E1d's "c0283 7/7" and E3's "5 of 5" therefore ran AC5 against files the real branch will not have. E4 names only the affected gate as unproven.
Critique: no raft-level fix exists. The tempting moves are all forbidden or fail:
- Copying c0263's specs into `tests/acceptance/c0263` early is promotion by hand, which is forbidden, and `done`'s own promotion would then collide with them.
- Editing c0283's check.sh during execution changes its approval contract, so `done` refuses c0283.
- No reordering helps, because c0263's specs are promoted only at the raft's `done`.
**This fix needs c0283's own design (its `check.sh`) to change.**
Consequences:
- c0283 is unfolded and re-prepped. The user re-approves it (a contract change), and folding it back makes a new `grouped:` record, which needs its own coherence review (003).
- The new path has to resolve in three states:
  1. sequestered, in the backlog and in `active/`;
  2. during `done`'s `runCheck`, still sequestered;
  3. after `done`, with c0263 in `done/` and its specs promoted. `c0120/finished.spec` requires every literal path in a finished check.sh to resolve from its home.
- A value computed outside a `bash -c` body is empty inside it unless it is passed as an argument (the c0284 note in the lesson below).
Recommendation: `./zn unfold R0099 c0283` for a minor re-prep that changes only AC5's two paths:
- Compute `C="$PWD/$("$ZN_ROOT/zn" find c0263)/acceptance"; [[ -d $C ]] || C="$PWD/tests/acceptance/c0263"` beside the existing `A=` lines, and pass it in: `bash -c '… lune run tests/run -- "$1/provenance.spec.luau" "$1/publish.spec.luau" tests/tooling/approve.spec.luau …' _ "$C"`.
- Run `./zn check c0283` twice: on a copy of the stack with the promoted `z-nile/tests/acceptance/c02{63,80,82,83,84}` copies removed, which is how `finish` and `done`'s `runCheck` see it; and on a copy with c0263 and c0283 moved to `done/` and their specs promoted, which is how `c0120/finished.spec` sees it. Then run `z-nile/check.sh --affected` with the new check.sh in the tree (lesson check-paths-from-the-home, its c0118 note).
- After the user re-approves and c0283 is folded back, raft review 003 runs on the new record.
- In the raft, remove the promoted copies from the prototype stack, rerun all five member checks, and record the results in a new E entry. Add to E4 that the member checks ran with every member's specs sequestered.
Lesson: z-design/check-paths-from-the-home

### F2 [medium] RC1 reads each extra member's document at `$ZN_ROOT/$dir`, but `./zn members` prints paths relative to the home, so RC1 fails for every member that really is emergent
Where: R0099/check.sh:16; design-refute-001 F4 ("fixed")
Evidence:
- RC1's body has `grep -q "^emergent: true" "$ZN_ROOT/$dir/$id.md"`.
- `ac.sh` changes to the home (`z-nile/`), and from there `./zn members R0099` prints `.tracker/issues/c0263` … (from the root it prints `z-nile/.tracker/issues/…`). RC0's own loop uses the printed path correctly (`bash "$dir/check.sh"`).
- Probe (`.cache/rv99-002/`): the root holds a `zn` stub whose `members` prints home-relative paths, and `root/z-nile/.tracker/issues/` holds the five members plus `d0999` with `emergent: true`. I ran RC1's body, copied verbatim from line 16, from `root/z-nile` with `ZN_ROOT=root`:
  - five members: exit 0;
  - five plus d0999: `grep: …/root/.tracker/issues/d0999/d0999.md: No such file or directory`, `d0999 is a member and not emergent`, exit 1.
- The real RC1 on this branch exits 0, because it has no emergent member.
Critique: the happy path never reaches the grep, so a run on the branch cannot show the defect. That is why F4's recommendation named four spec cases, and they were not run. Once readied, the file is sequestered, so one emergent issue during execution stops `done` (lesson z-raft/plan-the-switch-over).
Consequences: none beyond the path. The `^emergent: true` front-matter test is right.
Recommendation: use the path as printed: `grep -q "^emergent: true" "$dir/$id.md"`. Rerun the probe's four cases (five pass; five plus emergent pass; five plus a non-emergent fail; four fail) against a stub laid out as `root/z-nile`, and record them in Experiments. This is raft-level, with no member change.
Lesson: z-design/check-paths-from-the-home

### F3 [medium] RC3 passes on a tree that has no `./zn who` at all; RC4's call-site check matches the definition; RC3 to RC5 were never run
Where: R0099/check.sh:18 to :20; R0099.md:123 to :125; Experiments (no entry for RC3 to RC5)
Evidence:
- **RC3.** On this branch (main's engine, no `who`), `./zn who c0263` exits 1 and prints 9,163 bytes of usage to **stdout**. Line 76 of that usage is `idea <id> [--text <rough>] …`. RC3's body, run from `z-nile/` with `ZN_ROOT` set, exits **0**: `bash -c` has no `pipefail`, so the pipe's status is grep's. The register-cap half holds, because a compile failure prints nothing on stdout. The claim "`./zn who` prints a real item's history" is not pinned: an unwired `cmd.who`, or an argument path that falls through to usage, passes. The real line shape is `2026-10-01 09:00  idea  human:Ann (from git)  (git)` (c0280 `who.spec:260`, `provenance.line` joins its parts with two spaces).
- **RC4.** `grep -q "provenanceOf(" engine/board.html` matches the definition `function provenanceOf(it) {` (stack `board.html:312`), so review 001 F5's "defined but never called" is not closed. The two call sites read `h += provenanceOf(` (:328 and :352).
- **RC5.** It is plausible but unproven. Main's board build under `GIT_TRACE` makes 30 git calls, 0 of them `cat-file`, with one trace line per call. The stack's only `cat-file --batch` on the board path is `who.luau:67`; `workread.luau` and `main.luau:6385` are off that path. But no E entry records RC5, or RC3 and RC4, running on the stack. F2 of review 001 asked for "first confirm on the prototype that the build makes no other cat-file call". Also, `grep -c "cat-file --batch"` would count `--batch-check` and `--batch-command` too. There are none on the board path today.
Critique: rewording the RC text does not help. Each RC must fail on the raft's own branch when its claim is about code not yet written, and RC3 passes there.
Consequences: none for members. Every edit is in the raft's `check.sh`, before it is sequestered.
Recommendation:
- RC3: `out=$("$ZN_ROOT/zn" run --time 120 -- "$ZN_ROOT/zn" who c0263) && grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}  idea  (human|agent):' <<<"$out"`.
- RC4: grep the call `h += provenanceOf(`.
- RC5: count `grep -cE 'cat-file --batch( |$)'`.
- Then run RC1 to RC5 on this branch, where RC3 to RC5 must fail, and on a throwaway clone of the stack, where they must pass. Record both runs in Experiments.
Lesson: z-raft/rc-pins-the-claims-it-makes

### F4 [low] The register numbers and the R0100 interface contradict measurement and R0100's own document, and review 001 F6's sentence is still there
Where: R0099.md:53 (main.luau "Agree"), :71 (Interfaces), :107 (E2), :133 (Risks); design-refute-001 F6
Evidence:
- **My measurements.** The probe `.cache/rv99-002/regs.luau` puts N `local function stubN() end` lines after line 1, calls `luau.compile`, and runs under `./zn run --time`.
  - `main.luau` of origin/main at c2833872, 94fb5235d, 5416ac7d9 and a65b4f41 compiles with 4 stubs and fails at 5 (`Out of local registers … exceeded limit 200`).
  - The stack's `main.luau` compiles with 1 stub and fails at 2.
  - So main has **4** spare, not "4 to 7 … fails at 8". The layers use **3** registers, not "3 to 6", and 1 is left, so E2's conclusion stands.
- **R0100's numbers.** R0100.md:88 names the same three locals ("R0099's layers add the top-level locals `mergerecords`, `provenance` and `lifecycle`").
- **Review 001 F6.** Line 53 still says "none adds a top-level local (c0263 moved `mergeRef` out; …)", the sentence F6 named, and the refute answered "fixed".
- **R0100's state and stack.** R0100 is **active** on origin/main (`status: active-falcon-lucky-otter`), not "prepared at the same time". Its document says R0099's "note of 206 locals is from before c0265's fix" and "`origin/main` alone has **4** spare; the stack … has **10**" (:143), because c0265 inlines eleven requires.
- **What that means for the heartbeat raft.** R0100 frees about six registers net. Landing first leaves R0099 about 7; landing second onto R0099's 1 also leaves about 7. Neither raft has to move names, so R0099's :71 ("Both rafts are already at Luau's 200-local limit") and :133 ("R0100 cannot land beside it without moving names into tables, and the same holds for this raft if R0100 lands first") are false. The two rafts state different facts about one shared resource.
- **The real exposure.** It is not R0100 but any raft that lands a top-level local in `main.luau` before R0099's last layer. That layer is the one waiting on R0096, which maximizes the window. The two such writers in flight add none: d0298 (R0096) compiles with 3 stubs on its base fa7a70dc and 3 on its prototype, and c0306 (R0107, active) compiles with 4 and 4.
Recommendation:
- Correct E2: main 4 spare, the layers 3, the stack 1, and the method (compile-only, stubs after line 1).
- Replace line 53's claim with the three locals.
- Correct :71 and :133 to R0100's measurement (R0100 frees room, so either order fits, and the second lander still recounts), and say R0100 is active.
- State that the one register is shared with every raft that adds a top-level local to `main.luau`. The executor recounts by the stub method after each merge of origin/main and at the last layer's start. RC3 stays the backstop.
Lesson: z-design/restated-rules-move-together (a refute's "fixed" whose sentence is still there), z-raft/cross-raft-order-written-in-both

### F5 [low] Stale text after the reorder and the two re-preps
Where: R0099.md:17, :19, :44, :45, :77, :85, :92, :131
Evidence:
- :45: "After the alias, `hint` loops over `AGENT_MARKERS`". Under the ruled order, `hint` loops over `AGENT_VARS`. Line 44 says so, and so does the stack (provenance.luau:109, `for _, name in provenance.AGENT_VARS do`).
- :44 "the flipped order is not prototyped and RC2 pins it" and :131 "The ruled order … was not prototyped" contradict E1c ("The alias order is the ruled one … both pass") and the stack commit 62fc6dac ("proto: AGENT_VARS defines the list, AGENT_MARKERS aliases it (c0282 last)"). What was never built is a prefix of the layers (c0263 to c0284 without c0282).
- :17 "about 2,380 changed lines": the sizes are now 970 + 690 + 140 + 320 + 300 = **2,420**. c0283 went from 100 to 140 in #353.
- :19 "`dispatcher.luau` and `publish.luau` (c0282; c0263)": `publish.luau` is c0263's and c0283's, as :59 and c0283's Touched modules say.
- :92 "c0266, c0302 and c0304 … all three are `new` with no raft": c0302 is in `done/` on origin/main (`./zn find c0302`, and E1d cites its landed spec). The wait still holds through c0266 and c0304, both `new` with `design: draft`.
- :85 "its `approved` row … is the first row the record's writers add": layer 1's `./zn provenance record` already writes `confirmed`, `ranked` and `unblocked` rows.
- :77, the c0264 bullet: R0092 is in `done/` (c0264's specs are promoted), so R0099 is the second to land, and the relabel of the five `*designed*` sentences (README:145 to :151) and Roadmap rows (:176 to :185) is now R0099's, unconditionally. Nothing checks it: c0264's promoted `intent.spec` checks label shape only ("the truth of each label … are check.sh's (sequestered, not promoted)").
Recommendation: fix these sentences. None touches a member or a pinned file. For the c0264 bullet, name the layer that relabels and the label it writes (`*exists*` once the item is done; c0264's vocabulary is `*exists*`, `*designed*`, `*captured*`), and drop the request to R0092's lead.

## Candidate lessons (for the lead to harvest)
- z-raft: a raft's prototype stack keeps every member's acceptance specs where the real branch will have them (sequestered, with no promoted copies under `tests/acceptance/<member>`), because a promoted copy hides any check line that names a promoted path until `done`. Check: does any member's `check.sh` name `tests/acceptance/<a member of this raft>/…`, and do all member checks pass on a stack with no such copies? (F1)
- z-raft (a note for rc-pins-the-claims-it-makes): an RC that greps a command's stdout must fail on the raft's own branch before the code exists. A usage text, a help line or a template can hold the word. Check: run each RC on the unexecuted branch; does every RC whose claim is about new code fail there? (F3)
- z-raft: a cross-raft resource (`main.luau`'s registers, a counter) is stated with one measured number in both rafts, re-measured when the other raft's document changes, and named for every raft in flight that spends it, not only the raft of the Interfaces section. Check: do both rafts' documents give the same spare count for the same base, and has each other raft touching the file been measured? (F4)

Verdict: changes
