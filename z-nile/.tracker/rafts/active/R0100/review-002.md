# Review 002: R0100 (code mode)
Inputs: layer 2 (c0274), `git diff R0100/1/c0265...R0100/2/c0274` (layer 2 at 815a6598b, layer 1 at d472c40b5), files read with `git show R0100/2/c0274:<path>`. Also read: c0274.md, its check.sh, acceptance/{plan,memory,takeover}.spec.luau, R0100.md, c0275.md (its hand-off rules for this layer), review-001.md.
Checked:
- Sequestration: `git diff --find-renames=100% --name-status origin/main...R0100/2/c0274` over check.sh and acceptance/ lists only `A z-nile/.tracker/issues/active/c0274/acceptance/watch.txt`. That is the watch map `./zn finish` writes (zz-test, Affected selection: "`./zn finish` is the only writer"), and its three lines are this layer's own sources. zz-review item 2 does not name that file yet; c0326 captures the gap. `results.txt` is also finish's record.
- The 200-local cap: I compiled padded copies of `main.luau` with `@lune/luau` (through `./zn run`). Layer 2 has 10 spare top-level locals and layer 1 has 11. The only new top-level local is `cm`, as the raft budgets.
- `z-nile/tests/lib/cachepaths.luau`: the one added line is `cm.file`'s literal, a `.cache` file in the checkout written with `sh.writeReplacing`. Reviewed and accepted.
- Repository safety and bounded commands: the diff adds no spec, check.sh or script. The swap pushes only `hb/*` refs, through `hb.netRun`, with the checkout's own identity. No guard file changed.
- The takeover decision (`setStatus`): the verdict is read once before the publish, inside a `pcall` that uses `hb.beatPaths()`. Inside the build, `canTakeOver` re-checks it against the stamp the fresh read of origin holds, and the build runs again after a lost push race. Every other outcome refuses with c0053's prefix and the reason. The checks run in the designed order: the carried-move stamp check first in the build, then the give-back refusal before any target, `done`'s check before the clean-tree check, and `release`'s check before `--force`. `fold` already refuses an old owner, because it needs the checkout's own claim.
- Not run: `./zn check c0274` and `z-nile/check.sh --affected`. The worktree is on layer 3 (`R0100/3/c0275`, with staged changes), so a run there is not evidence for layer 2, and it must not be moved. The author's log records `./zn check c0274` 4/4 and an affected run of 776 passed.

### F1 [medium] `done` drops the work claim's memory before the two steps that can roll the landing back
Where: z-nile/engine/main.luau:5937-5938 (`bound = true`, then `cm.drop(raft.id)`); 5983-5984 and 5990-5993 (reading and retargeting each layer's PR base: `rollback()`, then `fail`); 6001-6009 (`git push origin HEAD:refs/heads/main`: `rollback()`, then `fail`)
Evidence:
- After the binding commit, `cm.drop(raft.id)` deletes `.cache/tracker-stamp-<R>` and `tracker-claim-<R>`.
- The steps after it call `rollback()`, which is `git reset --hard layerBranch` once `bound` is set, and then `fail(... (rolled back))`. The usual cause is a push to main that is rejected because main moved while the gate ran.
- After such a rollback, origin/main still shows the raft as active and claimed by this worktree, but the worktree remembers nothing:
  - `./zn beat R`, or a restarted `--watch` loop, is refused with `beat: this checkout does not hold R's claim (use --adopt to take it on)`.
  - A retried `./zn done` skips the old-lead refusal, which runs only when the memory holds an `active-` stamp (main.luau:5734-5735).
- Layer 3 makes this worse:
  - c0275's autobeat beats only the claims a worktree remembers.
  - Its background beater ends when `cm.read(id, home)` is empty (c0275.md:136: "its worktree no longer holding the claim").
  - So the claim goes silent while the retried `done` reruns the affected gate, and after 15 minutes it reads lost.
  - If someone then stops and readies the raft, the old lead has no memory, and its next `done` is not refused. AC3's "the old lead's `done` is refused" exists to prevent exactly that.
Critique: The Design says the memory ends "right after the binding commit (`bound = true`), so a failed binding keeps the memory", and the code follows that literally. But the binding commit is not the last step that can fail and undo the landing. The retarget and the push both undo the binding without giving the memory back. The tempting fix is to write the memory back in `rollback()`. That puts a claim write into a rollback that also runs before `bound` is set, when nothing was dropped. And a crash between the drop and the rewrite still loses the memory.
Consequences:
- If `done` dies after the push but before the drop, the worktree keeps the memory of a raft that is now done on main. That is harmless:
  - `beat` answers `R is done: no claim to beat` (the not-a-claim check runs first).
  - `done` refuses a raft that is not active.
  - c0277's plain lookup treats a remembered claim that origin/main no longer shows as over, so it discards that finished worktree, but only after such a crash.
- c0275 drops its marks "beside `cm.drop`", and drops the branch "after `done` has landed on `main`". Both move with this line. That agrees with R0099's order: "this raft's branch drop and sweep after the push".
Recommendation:
- Move `cm.drop(raft.id)` to just after the `if hasOrigin()` push block (after line 6009, before the switch to `main`), so the memory ends only once the binding commit is on origin.
- Add a case outside the sequestered folder. No existing spec drives `done`'s rejected push (`git grep "could not push the binding commit" -- z-nile/tests` finds nothing). The case: a fixture whose git shim rejects `HEAD:refs/heads/main` once. After the failed `done`, `.cache/tracker-stamp-<R>` still holds the adopted `active-` stamp and a bare `./zn beat <R>` beats. A later `done` that lands removes the file.
- If the fixture's cost rules out a case, update the reasoned Rules row "`done` ends the work claim's memory" in the Verification log so it names the new line and gives the reason.
- Tell layer 3's executor that c0275's mark drop goes beside the moved line.
Lesson: z-design/refusing-memory-names-how-its-owner-gets-back-in

### F2 [low] `stop`'s verdict read can end the command, and its fetch is unbounded
Where: z-nile/engine/main.luau:6820-6831 (`pcall(function() return hb.judgeAll(originPaths()) end)`); 1500-1507 (`originPaths`); 1584 (`hb.claimsOf`: `originRoots() or fail(...)`); 137-140 (`fail`)
Evidence:
- `fail` writes to stderr and calls `process.exit(1)`, which a `pcall` does not catch.
- `originPaths()` calls `fail` when origin/main's project roots cannot be read, and so does `hb.claimsOf`.
- So when origin/main's `z-nile/projects.toml` is missing or broken, `./zn stop` exits after it has pulled the main checkout and before the give-back. The Design says this read fails closed: the stop should record `(claim S, unjudged)` and go on.
- Prep met the same trap in `setStatus` (c0274 E3, c0114/window: "the verdict read called `originPaths()` … which fails the command") and fixed it there with `hb.beatPaths()`, which returns nil. `stop` still calls `originPaths()`.
- `originPaths()` also fetches with plain `sh.git`, not through the bounded `hb.netRetry`. The Design says every network call of the takeover goes through the bounded wrapper.
Critique: `stop` is the only give-back of a readied raft. A record it cannot read must not block it. Catching the exit is not possible with `pcall`.
Consequences: none beyond the call site. The subject records `unjudged` in that case, as it does when the beats cannot be read.
Recommendation:
- In `stop`, read with `local paths = hb.beatPaths()`. Judge only when it is non-nil (`pcall(hb.judgeAll, paths)`); otherwise leave `note` at `unjudged`.
- A case that stops a raft on a fixture whose origin has no `projects.toml` (c0114/window's shape) is optional. Without it, note the change in the Verification log.
Lesson: zz-test/pin-fail-safes-where-they-act

### F3 [low] The old owner's texts are written in more than one place
Where: z-nile/engine/main.luau:1705-1707 (`hb.lostText`); z-nile/engine/heartbeat.luau:330-332 (`heartbeat.lostText`); the refusal endings at main.luau:2080, 2087, 2895, 5742
Evidence:
- The Design's pure list says `heartbeat.lostText(id, originStamp?) … (main.luau's lostText delegates)`. Instead, `hb.lostText` keeps its own copy of the same two strings. `beat`, `release` and `done` use that copy; `setStatus` uses `heartbeat.lostText`.
- Each call writes its refusal ending in full. "this checkout's work is no longer the claim's; stop here (./zn lost lists lost work to pick up)" appears at 2080 and 5742. "this checkout's claim is gone; do not give it back (…)" appears at 2087 and 2895.
- The Design says the old owner's give-back is refused "with the same text" as its carried move. The code gives it a different ending.
Critique: The layer rule lets c0275 decide who tells the old owner first, and in which words. With two copies, one will drift from the other. The specs pin only the prefix, so nothing would catch it.
Consequences: none. The strings are identical today.
Recommendation:
- Make `hb.lostText` return `heartbeat.lostText(id, now)`, or replace its call sites.
- Either give each refusal kind one helper for its ending, or record in the Verification log why the give-back keeps its own ending.

### F4 [low] U1, the executor's Phase 1 probe, is not recorded
Where: c0274.md, Unknowns & experiments (U1, "open, the executor's Phase 1"); Implementation steps, step 1; Verification log, 2026-11-14
Evidence: Layer 2's log records the port, the check, the affected run and the slow specs. Layer 1's log records "U1 passed" for its own probe (a single create with the executor's credential). Nothing records layer 2's U1: one atomic push that creates one `hb/` branch and deletes another, made with the agent's token.
Critique: Nothing is wrong at run time. The swap is best effort: a refused swap is reported and the claim stands, and takeover.spec's "a refused swap is said" covers that. But the dispatcher path (c0275) depends on knowing whether the agent's credential can make this push, and the Design makes it the executor's first step.
Consequences: The probe touches the real origin. It must use well-formed names only (`hb/preparing-probe-<w>-<w>`) and delete both branches afterwards.
Recommendation: Run U1 as the Design words it, through `./zn run --time 120 -- …`. Record pass or fail in the Verification log. On fail, name the fallback that applies: the dispatcher pushes the swap (c0275).

### F5 [low] Three doc and usage-text errors
Where: z-nile/skills/zz-rules/SKILL.md:202 ("Taking over lost work"); z-nile/skills/z-design/SKILL.md:15; z-nile/skills/z-run/SKILL.md:12; z-nile/engine/main.luau:55
Evidence:
- **zz-rules, `done`'s text.** It says the old owner's `./zn done` is refused "with `<id>'s claim was taken over (now <stamp>)`". After a stop with no ready, it says `<id>'s claim ended` instead (main.luau:5742, where `at` is nil).
- **zz-rules, a repeated rule.** The same sentence says "never over a remembered different stamp, no worktree re-adopts a claim over its remembered stamp". That is one rule twice.
- **z-design and z-run, the taker's worktree.**
  - z-design tells the taker to claim "in the worktree you will work in (never in the old worker's checkout)". z-run says "in a worktree that holds no claim of the old lead's".
  - On the same host, step 1's `./zn worktree prep-<slug>` (and `./zn worktree <R>`) returns exactly that checkout, and this layer offers no other way in.
  - A taker who follows z-design there claims in the old worker's checkout. The claim overwrites that checkout's memory, so if the old owner comes back there it reads `held` and is never told. No engine check catches this; only the text guards it.
  - Layer 5's numbered copy closes the gap, and the stack lands with it. But c0274's Assumptions record only z-stop step 4's wait on c0277, not this one.
- **Usage line.** The `beat` line's description starts at column 57. Every other line in the usage text starts at column 49.
Critique: zz-rules is the reference that other skills and agents quote. The worktree sentence is an instruction a taker on the same host cannot follow with this layer alone.
Consequences: Every AC4 phrase must stay: in zz-rules `--adopt`, `live or parked`, `(takes over` and `taken over (now`; in z-design `lost prep` and `origin/prep-<slug>`; in z-run `lost raft` and `--adopt`.
Recommendation:
- zz-rules: append "(`<id>'s claim ended` after a stop with no ready)" to the `done` clause, and delete one of the two re-adoption clauses.
- The worktree sentences: in the raft document (Risks, "Stopped and readied again"), record that layer 5's rewording replaces them, and name the sentences. A taker on the same host then gets layer 5's numbered copy, and layer 5's executor knows which sentences to replace.
- Usage line: wrap it so its description starts at column 49.
Lesson: z-design/instructions-runnable-where-they-run

## Judged criteria (code mode only)
- None: c0274 has no Judged criteria. Each Checked criterion has code that implements it as the Design states:
  - AC1: `takeoverPlan`, `canTakeOver`, `takeoverRefusal`, `holds`, `lostText` and `stopNote` are pure.
  - AC2: every claim path writes `cm`; `cmd.beat` binds the beat to the memory.
  - AC3: the takeover happens only on an explicit lost verdict, re-checked inside the build. The swap is one atomic push with a lease on each branch and one retry. Members and every other carrier of the old stamp follow. The old owner's carried move, give-backs, `release` and `done` are refused, and `stop` records its verdict in the subject.
  - AC4: the phrases are present.
- Two gaps remain. F1 is a path by which AC3's "the old lead's `done` is refused" fails after a rolled-back `done`. F5 covers wording.

Verdict: changes
