# Review 005: R0100 (code mode)
Inputs: layer 3 (c0275, Automatic heartbeats), `git diff R0100/2/c0274...R0100/3/c0275`. Layer 3 is at 98e15b324aa767cbc75ad096b6b4b1df757c9586 and layer 2 at 420464d67bbef4b7e9f59047a0903d46072a406c (layer 3 stacks on it). The local `origin/main` is 59831e01d; its `reap.luau`, `check.sh` and `cmd.sync` match the stack's base f99ccb0b5. I read the files with `git show R0100/3/c0275:<path>`. Also read: c0275.md (Design, Unknowns, Rules and mutants, Acceptance criteria, Verification log), its check.sh, acceptance/{plan,reap,autobeat}.spec.luau, proofs/beater.spec.luau (its setup), R0100.md (Whole-raft design, Layer rules, Interfaces, Experiments, Risks), and final-review-001.md. Its F6 (ensureBeater reads before it locks) is known and not repeated here.
Checked:
- Runs. Each ran in a scratch repository made with `git archive` under this worktree's `.cache/`, never in the worktree, and each through `./zn run`. The slow runs went one at a time.
  - `./zn check c0275` on the layer-3 tree: 4/4. AC3's three real-time proofs were included.
  - `z-nile/check.sh --project z-nile --affected --base <layer-2 commit>`, in a scratch repository whose `main` is the layer-2 tree and whose branch is the layer-3 tree (the same 23 files and +1774/-46 as the real diff): GATE PASSED, 134 spec files, 783 passed, 0 failed. That matches the Verification log.
- Sequestration: `git diff --find-renames=100% --name-status R0100/2/c0274...R0100/3/c0275` over check.sh, acceptance/ and proofs/ lists only `M .../c0275/acceptance/watch.txt`. That is the watch map `./zn finish` writes. Its new lines (`lib/sh.luau`, `tests/lib/cachepaths.luau`) are this layer's own sources. No check.sh, spec or proof changed.
- Probes, all bounded:
  - origin/main's `reap.decide` and this layer's, over one beater's process table, as F1 shows.
  - Whether macOS `ps -o command=` cuts a long beater command line when it writes to a pipe. It does not: 277 characters came back whole, so `hb.beaterAlive` reads the whole line.
  - The cost of the per-command calls, as F3 shows.
  - Whether a perl `$0` rename shows in `ps`, as F1's Consequences show.
- `sh.run`'s retry. It applies only to `git` with `fetch` as the first argument and the text `cannot lock ref`, and it runs the same command once more. A fetch is idempotent. The only cost is one second, and only on that failure. `hb.netRun` goes through `perl`, so it is not retried twice. `publish.commit` uses its own `git` and keeps its own back-off. `git -C <dir> fetch` and `process.exec` fetches stay outside the retry. No call site is inside a callback that cannot yield. I found no caller whose behaviour depends on a fast lock failure.
- The reaper's new rules. `isBeater` needs `bounded.pl … -- <path>/zn beat <id> --watch`. `underBeater` spares only from the orphan rule. The marked rule and the session rule still apply. `sessionBeater` cannot fire when `under` is nil: dropping that guard would match every process, and reap.spec's `pids({...})` with no `under` kills that mutant.
- Repository safety: the proofs and specs use fixtures under `.cache/c0275-*`. A beater started in a fixture stays in the jail, because the sandbox is inherited across `setsid`, and the jail's sweeper stops it. The real worktree's beater pushes only `hb/*` with the checkout's own identity, so the tripwire, which flags only fixture-authored refs, does not fire. `cachepaths.luau` gains two reviewed lines.
- Bounded commands: the detached beater is `./zn run --time 3600` (bounded.pl). The detacher waits at most 5 s for its parent to leave, then gives up. Nothing in the diff starts an unbounded process.
- `./zn lessons` searches I ran: beater, detached, reaper, session, old engine, migrate, pcall, mutant, texts.

### F1 [medium] An engine from before this layer, still running in a worktree that has not merged `origin/main`, stops every live beater in the repository at its first `./zn sync` or gate
Where: `z-nile/engine/reap.luau:296-318` and `:380-415` (the beater rules exist only in this layer's engine); origin/main's `z-nile/engine/main.luau:2274-2276` (`cmd.sync` calls `reapAuto()` before it fetches or merges); origin/main's `z-nile/check.sh:111` (`./zn reap --auto`); the old reaper's scope, the git common dir's parent (the main checkout, which holds every `.worktree/*`); c0275.md, Chore checklist, "Existing work" (b); c0275.md E1(b).
Evidence:
- Probe (`.cache/review005-probe`, through `./zn run`). The process table holds one beater: `perl <wt>/z-nile/lib/bounded.pl --time 3600 -- <wt>/zn beat c0010 --watch --session 77`, with ppid 1, age 120 s, its cwd in a worktree, and its `bash` and `lune` children. origin/main's `reap.decide` with the default scope answers `would stop 100 orphaned (its parent is gone) tree 2`. This layer's answers nothing.
- The old `cmd.sync` calls `reapAuto()` on its first line. So the first `./zn sync` in a worktree still on a pre-c0275 engine stops every beater in every worktree that is older than a minute. Only then does it merge the new engine. The old gate does the same (`./zn reap --auto` before its specs).
- Who runs that first sync: z-design, z-raft, zz-execute Phase 0 and z-work all start with `./zn sync` in a reused worktree, and `./zn start` refuses with `run ./zn sync first`. This repository registers 98 worktrees. The provenance raft R0099 is built at the same time in its own worktree, on its own engine, with its own syncs and gates.
- What a stop costs: a stopped beater comes back only with the next `./zn` command in its worktree. A session that waits on the user, which is the case the user's "Background beater" (Q1) is for, reads lost 15 minutes after its last beat. `./zn lost` then lists it first, and z-design or z-raft takes lost work first, so a live prep can be taken over.
Critique: Existing work (b) says an old worktree "runs its own engine until it merges origin/main: no autobeat before". It does not say that the old engine's reaper acts on the new beaters of every other worktree. E1(b) found that a pre-change reaper stops a beater, but the fix covered only the reaper that ships with the layer (zz-test/detached-helpers-meet-the-reaper was applied to one reaper of the several that will run). The tempting fix is one sentence in Existing work.
Consequences:
- A sentence alone leaves the window open for as long as any old worktree is used.
- Telling operators to run `./zn sync` in each active worktree after landing triggers the stop, because the old sync reaps before it merges. The update that does not is `git -C <worktree> merge origin/main`.
- A beater that survives the old reaper must either not look ownerless to it (an ancestor outside its CHAIN) or not be ORPHANABLE by name. A perl `$0` rename looks easy, but on macOS `ps -o command=` then shows the process's environment after the new name. I tried it: `zn-beater c0010 … BUN_OPTIONS=…`. The reaper's `command` field is meant never to carry the environment, so that is not the way.
- A waiting parent such as `/usr/bin/time` would change the process the pid file names. `hb.beaterAlive`'s `isBeater` and `reap.beaterSession` would then have to match the new top (or its child). bounded.pl's own orphan check would gain that parent as its lifeline.
Recommendation: Choose one and write it, with its cost, in c0275's Existing work and in R0100's Risks:
- (a) Accept the window and say how it closes. The landing PR lists the active worktrees (already required). Each one is brought forward with `git -C <worktree> merge origin/main`, never with a first `./zn sync`.
- (b) Make the beater survive a pre-c0275 reaper with a waiting parent whose name the old CHAIN does not hold, update `isBeater`, `beaterSession` and `hb.beaterAlive` to the new process shape, and add a tooling case that runs origin/main's `reap.decide` and this layer's over the beater's real process shapes.
- In both, add the old-engine run to E1's record.
Lesson: z-design/new-rules-migrate-existing-work

### F2 [low] One beater per claim is not assured even after final-review F6's fix: two commands can both take a stale lock, and an interrupted start leaves a beater that no pid file names
Where: `z-nile/engine/main.luau:1992-1997` (`hb.startLock`), `:1999-2043` (`hb.ensureBeater`), `:2131-2150` (the ticker and `hb.finish`'s `task.cancel`).
Evidence:
- The stale branch of `hb.startLock` is `rmdir "$1" && mkdir "$1"`. Commands A and B both fail the first `mkdir` on a lock older than a minute, and both see it stale. A removes it and makes its own. B's `rmdir` then removes A's fresh, empty lock, and B's `mkdir` succeeds. Both return true.
- Nothing releases the lock on an error between `hb.startLock(id)` (`:2020`) and `sh.run("rmdir", { lock })` (`:2039`). `sh.git` (`:2024`) and `sh.writeReplacing` (`:2037`) throw, and the callers' pcalls catch it above the rmdir.
- The same window is cut short when `hb.finish()` cancels the ticker (`:2149`) while the ticker's autobeat is inside `sh.run("env", args)` (`:2034`), or when the command is interrupted there. The detached child was already forked and has left the group, so it runs on. The pid file is never written, and the lock stays fresh. For a minute, every command returns at "another command is starting it". After that the lock is stale, no pid file names the first beater, and the next command starts a second one.
Critique: F6 fixes the order (read before lock) and the starter's window. These two causes end the same way, with two loops for up to an hour and one pid file, and they survive that fix.
Consequences: The starter cannot write a pid before the daemon exists, so only the beater can know that it is a second one.
Recommendation: Fold these into F6's fix:
- Release the lock on every path: run the body in a pcall and remove the lock after it.
- Make `beat --watch` exit at its start when the claim's pid file names a live beater other than its own runner (its parent's pid), so a duplicate ends at once whatever started it.
- Add one non-sequestered tooling case: a pid file that names a live stand-in beater, and a second `beat --watch` that exits at once.

### F3 [low] The autobeat starts a beater for every mark on every command before it knows the claim stands, and spends about ten processes per command on it
Where: `z-nile/engine/main.luau:2089-2090` (`hb.ensureBeater(id)` before the due check), `:2009` and `:2012` (two `inMainCheckout()` calls), `:1855`, `:1904` and `:1911` (three more in an attempt), `:1893-1898` (`hb.inMain`, a memo none of them use); c0275.md, Scalability ("With claims held, per claim a file read and a `kill -0`").
Evidence:
- Cost. Every `./zn` command in a worktree with one mark, inside the interval, runs:
  - `git rev-parse` and `git remote get-url` (for `hb.inMain` and `hasOrigin`);
  - the fence script twice (`guarded`, `checking`);
  - for the mark: `kill -0`, `env LC_ALL=C ps`, and `inMainCheckout()` twice, each call being `git rev-parse --show-toplevel` and `git worktree list --porcelain`.
- Timings, from 10 runs each through `./zn run` in this worktree: rev-parse 10.0 ms; `worktree list` 17.9 ms (98 worktrees); `ps` 3.2 ms. The two `inMainCheckout()` calls alone cost about 56 ms per mark per command, and the autobeat had already returned early if `hb.inMain()` said this was the main checkout.
- Starts that cannot succeed. After `./zn stop <R>` in the main checkout, or a takeover, the old worktree keeps its memory and its mark until its next command after the interval. Until then, each command's ensureBeater sees `held` (the memory is there) and a dead pid. It spawns a beater whose `beat --watch` fails at once (`beat: R0010 is prepared on origin/main: no claim to beat …`, or the taken-over text, appended to the log). That is up to five minutes of commands, each starting a detached perl, a runner and a Lune engine. Layer 5 removes the takeover case, because a discarded worktree's commands are refused before `hb.begin` (R0100, Layer rules 4). It does not remove the `stop` case or a prep whose `prepared` has merged.
Critique: Nothing here is wrong, but every command pays for it, and the Design understates the cost.
Consequences: ensureBeater cannot learn that a claim ended without a fetch. The beater can, because it reads `main` at its start.
Recommendation:
- Use `hb.inMain()` in ensureBeater, `hb.attempt` and `hb.writeMark`.
- Ask `kill -0` first, and read `ps` and the rest only when the pid is dead or missing.
- For starts that cannot succeed, either state in the Design that they happen and cost one engine start each, or let a beater that is refused at its start write that refusal beside its pid file (the stamp and the reason), so that ensureBeater skips that stamp until the mark is due.
- Correct Scalability to the measured cost.

### F4 [low] A `fail` inside the automatic beat's pcall exits the command the beat rides on
Where: `z-nile/engine/main.luau:1589` (`hb.claimsOf`: `originRoots() or fail(...)`), reached from `hb.beatOnce:1756` (every autobeat, tick, first beat and beater tick) and `hb.dropBranch:1938` (after a give-back, `release`, `stop`, and `done`'s landing); the pcalls in `hb.attempt`, `hb.autobeat`, `hb.firstBeat` and `hb.dropBranch`.
Evidence:
- `fail` writes its text and calls `process.exit(1)`, which a pcall does not catch.
- `hb.beatPaths` read origin/main's registry a moment earlier. claimsOf reads it again through `originRoots()`, on the moving `origin/main` and not at the sha `at` it was handed. A read that fails between the two (a sibling's fetch, a git error) has three effects:
  - it ends `./zn commit`, or any other command, inside `hb.begin`, before its handler runs;
  - it ends `./zn new raft` after its publish, before `mergeOrigin()` and its membership writes;
  - it ends `./zn done` with exit 1 after the landing, before `landed <R>`.
- The Problem says: "A beat never fails the command it rides on".
Critique: This is rare, but it is the shape of the lesson harvested from review-002, and it now sits on every command.
Consequences: claimsOf has other callers (`judgeAll`, through `lost` and `status`) whose failure may stay a fail.
Recommendation: Give the heartbeat path a claims reader that returns its failure: it reads the roots at `at` and returns nil and the reason. beatOnce and dropBranch branch on that result. The other callers keep the failing form. Add a tooling case in which origin/main's registry cannot be read on the second read.
Lesson: zz-arch/fail-inside-pcall-is-not-caught

### F5 [low] U1 and U2, the executor's Phase 1 probes, are not recorded, and no case makes `done`, `land` or `dispatch` tick
Where: c0275.md, Unknowns & experiments (U1 and U2, "open, the executor's Phase 1"), Implementation steps 1, Verification log 2026-11-14; `z-nile/engine/main.luau:2131`; Rules and mutants (the row "a long outer command ticks while it runs").
Evidence:
- The log records the port, `./zn check c0275`, the affected run and the slow specs. It records nothing for:
  - U1: whether a beater started from a real Claude Code tool shell ends within seconds of the `claude` process, and whether a real `/clear` stops it through the SessionEnd hook;
  - U2: the Cursor agent's process name, which `heartbeat.SESSIONS` covers by listing both guesses.
- `proofs/long` runs `./zn check`. No case runs `done`, `land` or `dispatch` with a mark, so a mutant that drops any of those three names from line 2131 survives every check. `./zn done` is the command that runs the gate.
Critique: The `/clear` stop depends on the SessionEnd hook, which cds to the project directory (`scripts/hooks/session-end.sh`). In a session started in the main checkout, that is the main checkout's engine, which has no beater clause until the stack lands. U1 would have shown this.
Consequences: Before the stack lands, U1 can only run against the layer's reaper (`./zn reap --session-end --dry-run --under <pid>` from the worktree). The log should say which reaper it ran against.
Recommendation:
- Run U1 and U2 as the Design words them, through `./zn run`.
- Record in the Verification log a pass, a fail, or "cannot run before landing, because …", with the fallback that applies.
- Move the long-command names into one table (for example `hb.LONG`), pin it in a non-sequestered tooling case, and add the mutant to the Rules table.
Lesson: zz-execute/log-each-cross-prep-run-and-how-it-was-applied

### F6 [low] Five restated texts say more than the code does
Where: `z-nile/skills/zz-rules/SKILL.md:202`; `z-nile/skills/zz-execute/SKILL.md:17`; `z-nile/skills/z-run/SKILL.md:12`; c0275.md:151 (Chore checklist).
Evidence:
- zz-rules says the beater ends "when the `claude` session that started it ends". `heartbeat.SESSIONS` also holds `grok`, `kimi`, `agent` and `cursor-agent`.
- zz-rules says "A give-back (`status <id> new`, `release`), `stop` and `done` drop the claim's heartbeat branch and mark". `stop` runs in the main checkout, where `hb.ended` drops the branch. The raft worktree's mark stays until that worktree's next command after the interval, which then says "claim ended".
- zz-execute, step 2, says "the claim itself starts `./zn run --time 3600 -- ./zn beat <id> --watch`". The claim zz-execute works on is `ready`'s, made in the main checkout, and it starts no beater. The beater comes from the `--adopt` in the bullet above.
- z-run says "Your claim keeps itself alive: it keeps itself alive from its first beat …", the same phrase twice in one sentence.
- The Chore checklist says "The commands' outputs gain, at most, one stderr line". A refused first beat writes its refusal twice (beatOnce's own line, then `hb.say`), and autobeat.spec pins "twice".
Recommendation:
- Name the CLIs, or write "the session's CLI".
- Say that after `stop` the worktree's mark goes at that worktree's next command.
- Say in zz-execute that the `--adopt` starts the loop.
- Use the phrase once in z-run (AC4 needs it only once).
- Correct the checklist line to the two lines the spec pins.
Lesson: z-design/restated-rules-move-together

## Judged criteria (code mode only)
None: c0275 has no Judged criteria.

## Lesson candidates (for the lead)
- zz-test/detached-helpers-meet-the-reaper, a note: a process meant to outlive its starter must also survive the reapers of the engines that still run in sibling worktrees after landing, not only the reaper it ships with. Check: which older engines still run a reaper over this process, and what does each decide? (F1)

Verdict: changes
