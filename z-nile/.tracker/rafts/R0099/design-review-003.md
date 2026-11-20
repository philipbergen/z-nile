# Review 003: R0099 (design mode, raft)
Inputs: branch `raft-provenance` at 0c7940cf (`R0099.md`, `check.sh`, design-review-001/002 with their refutes, `harvest.md`); the five member folders (documents, `check.sh`, `acceptance/`, c0284's `prototype.patch`); origin/main b1536c1b (two tracker-only commits past a3592884: c0267 claimed, c0359 captured); the prototype stack `.worktree/proto-provenance-stack` at 302601d9; `origin/proto-c0280` 009ea39d; the heartbeat raft's worktree `.worktree/R0100` at 75672be8 and `R0100.md` on origin/main; `R0106.md`; `z-nile/engine/main.luau` (`cmd.find`, `hereDir`, `guarded`, `reviewCovers`), `stack.luau`, `raftplan.luau`, `lib/ac.sh`, `tests/acceptance/c0120/check-paths.spec.luau`, `tests/acceptance/c0264/roadmap-unique.spec.luau`. Probes ran through `./zn run --time`, from this worktree's `.cache/rv99-003/` (`rc.sh`, the shared clone `mt/`, the merged `main.luau`) and `.cache/rv99-002/` (`hash.luau`, `regs.luau`); they are left there.
Grouped: [c0263@1b93fc9d0c76, c0280@9db248601f55, c0282@c7064c6ab955, c0283@b55b5368083c, c0284@27c0dce08c9e]

What holds:
- **The record.** `raftplan.recordHash` over each member's tracked folder (`.cache/rv99-002/hash.luau`) gives the five hashes quoted above, which equal the front matter's `grouped:`. The member folders on this branch differ from origin/main only in the `raft:` line, which the hash leaves out.
- **The Order.** The `Order & dependencies` section names c0263, c0280, c0283, c0284 and c0282, each once, and no other id (the pattern `stack.order` reads, `[fdc]%d%d%d%d`). `./zn stack R0099` prints the five layers in that order. The order follows every `depends_on`.
- **c0283's AC5 (item a).**
  - `P` is `$PWD/$(zn find c0263)/acceptance`. ac.sh's `cd` starts from the physical toplevel, so `$PWD` is physical. The `zn` wrapper recomputes `ZN_CWD` on every call, and `cmd.find` reads the local store, so from the home it prints `.tracker/issues/c0263`. After `ready` it prints `.tracker/issues/active/c0263`.
  - After `done`, promotion moves `acceptance/` out of the item folder (`done/c0264` has none), so the fallback `tests/acceptance/c0263` is the path that exists.
  - If `zn find` fails, its output is empty and AC5 falls back to the promoted path. Before promotion that path fails loudly, so it never gives a false pass.
  - c0120's `check-paths.spec` treats a word that contains `$` as not literal. AC5's literal paths (`tests/tooling/approve.spec.luau`, `c0116/promote`, `c0117/dispatch`, `tests/tooling/dispatch-texts`) all exist.
  - I ran `bash .tracker/issues/c0283/check.sh` on the stack: 7/7 in 54 s, with `P` resolving to the sequestered `.tracker/issues/c0263/acceptance`.
  - No other member's `check.sh` names a path under another member's id. I grepped every `check.sh` and every spec for `acceptance/c0…` and `issues/c0…`: the only cross-member path is c0283's fallback.
- **No earlier layer reads a later layer's code (item b).**
  - I grepped the specs of c0263, c0280, c0283 and c0284 for the names each later layer adds: c0280's `fromTrailer`, `select`, `merge`, `workerOf` and `trail.cut`; c0283's `AGENT_VARS`, `approved` and `approvedPublishProblem`; c0284's `boardprov`, `trail.cuts` and `logArgs`; c0282's `AGENT_MARKERS`, `ENV_VARS`, `raftDetail`, `raftedProblem`, `ZN_VIA` and `lifecycle`. Each spec uses only its own names and those of earlier layers. c0284 uses `who` and `provenance.line`, both from c0280.
  - c0283's code on the stack (`cmd.approve`, `publish.luau`, `fixture.exec`) uses no c0282 name.
  - c0263's `record.spec` clears the agent variables itself, so it does not depend on c0283's `fixture.exec` scrub.
- **The RC lines.**
  - RC1's body, run on this branch, exits 0.
  - I ran RC2 to RC5 under the real fence on the stack (`.cache/rv99-003/rc.sh` sources the stack's `ac.sh`, so the checkout answers `guarded`). All four pass in 5.4 s. The `GIT_TRACE` of RC5 holds exactly one `git cat-file --batch` line among 48.
  - R0100 does not change that count. On its board path, `hb.boardVerdicts` returns at `guarded(true)` before any fetch. Its only other `"cat-file", "--batch"` calls are main's metrics `readBatch` and `workread.catBatch`, and neither is on the board path.
- **The heartbeat raft (R0100, now finished).**
  - Registers, by the stub method: origin/main has 4 spare and R0100's tip has 10. This stack has 1. The stack merged with R0100's tip (F3) has **7**, as E2 says.
  - R0100 inlines `brokerLib`, `claimsLib`, `compactLib`, `dispatchLib`, `gateLib`, `openlist`, `pathsLib`, `raftcheck` and `watchcmd`. None of R0099's added `main.luau` lines uses any of them.
  - In R0100's final `setStatus`, every refusal (the old owner's give-back, the takeover's refusals) returns a string from the builder before `return changes`. c0282's row is added inside the target loop. So a refused give-back publishes no row, which is the contract R0099 states.
  - R0100 adds no new `setStatus` caller.
- **Lessons.** `./zn lessons --uncovered R0099` prints "every finding is covered". `./zn lessons --check` passes.

### F1 [low] The raft's overrides of members' Implementation steps sit in Experiments, unassigned to layers, and the resolved code is partly unpushed
Where: R0099.md:45 ("each raft-level resolution (the alias, the streamed read of E1b) is recorded in that member's Verification log"), :96, :101 to :103, :105 and :108; c0284.md:189 and :190 (Implementation steps 1 and 2); `c0284/prototype.patch`
Evidence:
- **c0284's step 1** says to "`git apply` the issue folder's `prototype.patch` … on the raft branch once c0263's and c0280's layers are in".
  - The patch's `who.luau` was cut from c0280's older tip (index 645396e7: `sh.run`, and one `git log -1` per merge).
  - I ran `patch -p1 --dry-run` of the whole patch over proto-c0280's final tip 009ea39d, the base the raft tells the executor to build on (:102). It printed "1 out of 6 hunks failed while patching 'z-nile/engine/who.luau'" (the `sideTrailers` hunk). `git apply` is all-or-nothing, so step 1 applies nothing.
  - The patch's `fronts` hunk, which does apply, is `process.exec(… stdio = { stdin = … })`. That is the form E1b found to deadlock on the real tree.
  - Step 2 asks for "the batched `who.sideTrailers`", which layer 2 already has (:101).
- **The raft's answers are scattered.** They sit in three Experiments bullets: :101 ("The c0284 layer therefore only adds `dir`"), :102 and :103. :103 gives the streamed read but names no layer.
- **:45's rule is incomplete.**
  - It lists two resolutions. It omits the c0284 patch override and the two row-list annotations for `approve --publish` (layer 3, :105 and :108).
  - It does not say whose Verification log records the streamed read: c0280's (`fronts`) or c0284's (the board that makes it large).
- **Unpushed code.** In the stack, 62fc6dac (the ruled alias order), 4c061d7e (the two annotations) and b4a35628 (the zz-rules `trace`/`done` rows) are on no remote: `git branch -r --contains` prints nothing. 202c32b5 (the streamed `who.fronts`) is reachable only from `origin/proto-c0283-publish`, which the raft cites for c0283's rule, not for this fix. :96 calls the stack "not pushed".
Critique: no wrong result follows. The deadlock form fails `c0057/open.spec` under the runner's `--time`, and RC5 catches it. But the layer-4 executor meets a member step that fails, and must assemble the answer from four bullets. The tempting move is `git apply --3way` or `--reject`, which brings in the deadlocking `fronts`.
Consequences: none for any member's contract, because the record goes in the Verification logs. Pushing the stack adds one scratch ref, as every `proto-*` already is.
Recommendation:
- In the Whole-raft design, beside :45, add one list of raft-level overrides per layer:
  - **Layer 3:** the two `{ provenance.Row }` annotations, and the narrowing of c0263's prose (in c0283's log).
  - **Layer 4:** c0284's patch applied without its `who.luau`. Check this with `git apply --check --exclude=z-nile/engine/who.luau` on the layer-3 tree. Then add only `who.luau`'s `dir` parameters and `who.spend` on c0280's file, and stream `who.fronts` (`process.create`, the keys written from a `task.spawn`, stdin closed, stdout read to the end). Record all of this in c0284's log.
  - **Layer 5:** the alias line (in c0282's log).
- For each layer, name the ref and commit that hold the resolved code. Either push the stack's three unpushed commits to a `proto-*` ref, or say that the raft text alone specifies them.
Lesson: z-design/prototype-reference-is-the-layers-own-diff, zz-execute/log-each-cross-prep-run-and-how-it-was-applied

### F2 [low] Member sentences that the raft or a ruling overrides are not named as superseded, and R0100's request about one of them is unanswered
Where: R0099.md:45, :75; c0282.md:26, :68, :73; c0283.md:85, :89; R0100.md:92 (origin/main)
Evidence:
- **c0282.md:73** says "A takeover's own record (c0265) is a `./zn provenance record` call of theirs." R0100.md:89 says it is c0317's. R0100.md:92 asks R0099's lead "to replace that sentence with c0317 and to name c0317 in R0099's Interfaces", and records the request as "not yet answered". R0099:75 names c0317 but never says that c0282's sentence is superseded.
- **c0282.md:26 and :68** say c0283 keeps "the dispatcher never merging a prep PR" and "the dispatcher's prep gate never merging; possibly a state file". The ruling the Theme quotes (:30) is "Dispatcher merges preps", and c0283.md:32 says "This issue touches no dispatcher code or text".
- **c0283.md:85** says c0263 (line 113) and c0280 (line 68) say c0283 adds "`approval`, `approvalProblem`, `exemptParse` and `exemptRender`". Both lines name `AGENT_VARS`, `approved` and `hint`, and no member names the other four.
- **c0283.md:89** says "c0282 owns `liveActor`". c0263.md:113 lists `liveActor` among its own callers, and R0099:48 puts it under c0263.
- R0099:45's "c0283's Interfaces say the same" is true of c0283's Interfaces block only.
Critique: these sentences are inside approval contracts, so editing them is forbidden. An executor who reads its member's document may act on one, for example by waiting for R0100 to record takeovers, or by "correcting" c0263's and c0280's text, which turns `done` against them.
Consequences: none beyond the raft text and the Verification logs.
Recommendation:
- In the Whole-raft design, add one bullet that lists each superseded sentence, the ruling or raft decision it yields to, and the member whose Verification log records it: c0282's takeover sentence yields to c0317, c0282's prep-gate sentences to "Dispatcher merges preps", and c0283's two Other-writers sentences to c0263:113 and c0280:68.
- Say in the R0100 Interfaces paragraph that this answers R0100.md:92.
Lesson: z-design/restated-rules-move-together

### F3 [low] Stale state after the re-preps, and the merge with R0100's now-finished stack is measured here but not recorded or checked
Where: R0099.md:19, :70, :76, :77, :92, :108, :122
Evidence:
- **R0100's state (:70 against :71).** :70 says R0100 "is prepared at the same time", and :71 says "That raft is active". In fact its five layers are finished: `./zn stack R0100` in `.worktree/R0100` shows c0274 to c0277 finished, with the final refute and trace committed, and the tip at 75672be8. So R0099 will almost certainly land second, and every "whichever lands second" line is its executor's.
- **My merge probe.** In a shared clone under `.cache/rv99-003/mt`, `git merge-tree --write-tree origin/proto-provenance-stack 75672be8` conflicts in four files only:
  - `main.luau`: one hunk, the top of `cmd.done` (c0282's `lifecycle.who`/`check` against c0274's old-lead refusal);
  - `board.luau`: the two `Issue`/`Raft` type blocks;
  - `README.md`: the board line;
  - zz-rules: the read-only list and the board row.

  `setStatus`, `dispatcher.luau` and `board.html` merge cleanly. With the `cmd.done` hunk resolved as keep-both (R0100's refusal first), the merged `main.luau` compiles with 7 stubs and fails at 8. No member check has run on that tree.
- **R0100's Roadmap rows.** R0100's tip `README.md` has two Roadmap rows each for c0265, c0274, c0275 and c0277: lines 163 to 166 say `exists` and lines 181 to 185 say `designed`. c0264's promoted `roadmap-unique.spec` refuses that ("two Roadmap rows for c0265"). R0099's members relabel rows 176 and 182 to 185 of the same table. :77 states the one-row rule for c0264/R0092 only.
- **c0260 (:76).** :76 says c0260 is "being re-prepared". It is prepared and rafted alone as R0106. R0106.md:34 says it calls `./zn provenance record` only when `provenance.luau` exists. Its Touched paths (R0106.md:27) include `audit.luau` and `main.luau`, which c0263 also changes, and R0106.md:35 says it adds no top-level local.
- **Cross-raft waits (:92).** :92 says "c0266 and c0304 are `new` with `design: draft`". Both are now `preparing` (still draft), which shortens R0096's chain.
- **Exit criteria (:122).** :122 says "RC1 to RC4 below" but lists RC5.
- **Shared surface (:19).** :19 says "`provenance.luau` (all four upper layers add to c0263's module)". c0284 adds nothing there: see its Touched modules and :40 to :43.
- **E1g's gate (:108).** E1g's gate run is red (895 passed, 4 failed), and the only standalone run of `remap-shapes` cited is from earlier code. I reran `tests/acceptance/c0263/remap-shapes.spec.luau` alone on the E1g stack: 5 passed, 0 failed, in 14 s.
Critique: none of this changes a member or an RC. But the R0100 merge is now cheap to prove, and if a member spec turns red on it, the red shows up at a layer that cannot change that spec. c0282 is the most exposed: it drives `status`, `fold`, `new raft`, `recombine`, `done` and the dispatcher, all of which R0100 changed, and it is the last layer, which already waits on R0096.
Consequences: an Interfaces bullet for the Roadmap table, and one new E entry.
Recommendation:
- Fix the sentences above.
- Add E1h: the merge-tree conflict list above, the keep-both resolutions, and the register count of 7. Then run `./zn check` for the five members on that merged tree, plus `z-nile/check.sh --affected`, and record the results.
- Add an Interfaces bullet: both rafts relabel their own rows in the one Roadmap table, and the second lander keeps exactly one row per id (c0264 AC10, promoted).
- Pass R0100's duplicate rows to its lead. They are R0100's to fix before its merge gate.
Lesson: z-design/design-the-execution-window, z-raft/cross-raft-order-written-in-both

## Candidate lessons (for the lead to harvest)
- z-raft: when the other raft of a cross-raft interface finishes its stack before this raft is readied, merge its tip into this raft's prototype stack, measure the shared resource on that merge and run every member's check there. `git merge-tree --write-tree` in a shared clone under `.cache` gives the conflict list without a checkout. With both stacks built, "whichever lands second" is no longer a guess. Check: is the other raft's stack finished, and has this raft's prototype been merged with its current tip? (F3)
- z-raft: a raft that overrides a member's Implementation step lists each override with its layer and the pushed ref that holds the resolved code. Examples are a `prototype.patch` that no longer applies on the layer below, or a form an experiment replaced. Check: does each member's first Implementation step still apply on the layer below as the stack builds it (`git apply --check`), and is every resolution the raft relies on reachable from origin? (F1)

Verdict: approve
