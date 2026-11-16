# Review 001: c0253 (design mode)
Model: claude-opus-5-5
Effort: default (the launcher's setting)
Inputs: prep worktree `.worktree/prep-worker-pull-loop` at 319e98d2b with the uncommitted c0253 folder (`c0253.md`, `check.sh`, `acceptance/{board,command,docs,loop,models,pure,reap,session}.spec.luau`, `experiments/` with `prototype.patch`, `mutation-results.txt`, `mutate.py`, `e2.sh`, `e2-final.txt`, `check-proto.txt`, `gate-affected-{1,2}.txt`, `promote-proto.txt`, `affected.txt`, and `harvest.md`) and the new lesson `z-nile/skills/zz-arch/lessons/new-boolean-flags-join-the-parsers-list.md`. Prototype `proto-c0253` a1c656713 on base 26265fa3a (`git diff 26265fa3a proto-c0253`: `supervise.luau`, `workloop.luau`, `workedge.luau`, `main.luau`, `models.luau`, `reap.luau`, `board.luau`, the docs). `./zn capture c0253` (capture 0e91b4d75, no marker). On origin/main 26265fa3a: c0248, c0249, c0250, c0252 (prepared), c0251, c0260, c0305, c0306, c0307, c0175 (prepared, and its sequestered `docs.spec.luau`), R0100's c0265, c0274 and c0275, commit 6ead1904d (#325); the engine at 26265fa3a (`dispatcher.luau` step env, `guardStart`, `resolveBin`; `modelstep.luau`; `credential.luau`; `publish.luau` broker branch; `adapters.luau`; `work.luau`; `models.luau` `walk`/`walkAt`; `z-nile/bin/git`; `zn`); the c0117 `dispatch-cli.spec`; skills zz-review, z-design, zz-arch, zz-test, z-work, zz-rules, z-raft; `./zn lessons` for stand-in, credential, tripwire, interface, headless, realpath. I ran nothing else: the machine is loaded, and `experiments/check-proto.txt` (13 of 13 on the prototype) and `mutation-results.txt` (72 of 72 killed on an assertion) are the run record I relied on.

What checked out: the capture is confirmed, the Problem and Solution are unchanged, and every Decided line is cited as worded, with the 2026-11-13 re-ruling of Q1 applied over the Idea's "a person rafts". The pure/loop/edge split follows zz-arch rule 4, and every loop is a bounded `for`. `parsePick` takes c0249's line and its exit 1 exactly. Every session gets `ZN_HEADLESS` and `ZN_MODEL` (c0250's Note) and the agent's token, never the person's. Every spec writes only under its own `.cache` fixture (through `trackerfix` and `fakecli`) and starts no detached process. E2 was bounded and wrote its stop file on exit. OC1 is a fair Observed, because no check may start a real model CLI. The new lesson is one another raft could fail. The design's core idea (a model-free loop that claims, starts a fresh session per raft, resumes it, and waits) is sound. What fails is mostly where it meets the layers below it and the dispatcher it was captured to sit on.

### F1 [high] Every session runs outside the dispatcher's guards while the supervisor holds the person's credential: no wrapper, no publish broker, no tripwire, and whether it may land is guessed from two variables
Where: captured Solution ("A thin loop over the engine's `next` and the dispatcher"); Modules (`workedge`), Chore checklist "Guards" (c0253.md:322), G5 (c0253.md:299); prototype `workedge.luau` 185-192 (the session environment), 266 (`canLand`), 104-107 (`zn`), `workloop.luau` 157 (`lander`); compare `dispatcher.luau` 866-884 (the step environment) and 694-697 (`guardStart` = `sweepRefs`, `pinOrigin`, `vetMain`), `publish.luau` 601-617, `modelstep.luau` 1-9.
Evidence:
- **(a) No wrapper.** The dispatcher's step gets `PATH = {repo}/z-nile/bin:…`, `ZN_REAL_GIT` and `ZN_REAL_GH`. workedge sets `env.PATH = process.env.PATH`. A supervisor session's `git push origin HEAD:main` or `gh pr merge` therefore reaches the real git and gh with the agent's token. zz-rules Merging says `main` "may have no branch protection … until then the server stops nothing", and today the wrapper is what refuses these.
- **(b) No broker.** No `ZN_PUBLISH_BROKER` is set. Every tracker publish a session makes (c0250's `./zn block`, z-raft's `new raft` and `fold`) takes publish.luau's other branch, `git push … {sha}:refs/heads/main`, with the agent's token. Under the ruleset of c0117 §8 ("updates restricted to the bypass list, the user the only bypass") it fails. Without that ruleset it lands unvetted. The branch's own comment says: "inside a dispatched step the agent's credential can't push to main: the dispatcher pushes it".
- **(c) No tripwire.** Between sessions the supervisor runs `{top}/zn ready|stop|block|lander` with the person's credential, and no tripwire runs before them. The dispatcher's `vetMain`, `pinOrigin` and main-checkout snapshot (zz-rules Dispatch, The tripwire: "origin's configuration … the main checkout's tracked and untracked files unchanged") have no counterpart here. A session runs as the user with `bypassPermissions`. It can edit `<main>/z-nile/engine/*.luau`, `<main>/zn` or `url.*.insteadOf` in the shared config, and the next `./zn lander` runs that code with the person's token. c0252 G2 relies on "the base's engine (the main checkout's)" being as `main` has it.
- **(d) `canLand` is inferred.** It is `ZN_HEADLESS == "" and ZN_DISPATCH == ""`. The README says "A worker on another machine needs a clone, its CLIs and a bot credential". On that host neither variable is set, so the supervisor runs `./zn lander`, and `done` pushes `main` with the bot token: c0252 G7 tells the two credentials apart only by these two variables. That is the agent's credential landing, against Q4 and Q10.
Critique: `modelstep.luau`'s header names the gap: "The dispatcher calls `launch` from its own loop, which adds the broker and the tripwire around the same start". The design calls `launch` bare. The fix an author reaches for is to copy `PATH = z-nile/bin:…` into workedge. That restores only the wrapper: the broker needs a process that serves it with the person's credential, and the tripwire needs a pinned start state.
Consequences:
- **The broker.** Serving one makes the supervisor a long-lived pusher of tracker state with the person's credential. It needs the run token, the fast-forward-only rule and `trackerstate` judging each request: the dispatcher's code, reused.
- **The tripwire.** It needs a defined start (the `main` the supervisor started on, advanced only by vetted commits) and a defined response: stop the supervisor, keep the claim, say why in `work status`. The user's "Keep same user, accept detection" makes detection the bar, not prevention.
- **The bot host.** Marking it needs a rule the person can see: a variable set for the supervisor itself on a bot host, or a key, documented in the README's other-host line.
Recommendation:
- **Start through the dispatcher.** Start every session through the dispatcher's model-step machinery, not around it. Either factor the step-environment builder (wrapper `PATH`, `ZN_REAL_*`, the agent credential, the broker folder and token) and `guardStart`/snapshot/`vetMain` out of `dispatcher.luau` into one module both call, or run each pick as dispatcher steps with a resume option added, which is the captured Solution.
- **Serve the broker** for the supervisor's sessions.
- **Run the tripwire** after each session and before each command that uses the person's credential. A trip stops the supervisor, names the item and keeps the claim.
- **Land only when a stated credential rule holds.** Decision for the user, in the approval session: how a bot host marks itself.
- **Cases:**
  - session.spec logs the session's first `PATH` entry and `ZN_PUBLISH_BROKER`, and asserts `z-nile/bin` first and a broker set;
  - a session that edits a tracked file of the fixture's main checkout is followed by no `lander`;
  - with the bot-host marker, `move` gives `wait-lander`.
- **Rules rows** with the mutants "no wrapper", "no broker" and "no tripwire before lander".
Lesson: zz-arch/tripwire-covers-every-interval

### F2 [high] The supervisor works in whatever checkout it was started from and reads facts and settings from that working tree: from a worktree it misses c0252's land requests and runs branch code as the lander, and from any checkout a session can rewrite the caps it runs under
Where: prototype `main.luau` 7800 (`top = process.env.ZN_TOP or "."`); `zn` 28-45 (a `work` command started in another worktree sets `ZN_TOP` to that worktree); `workedge.luau` 105 (`{top}/zn`), 108-112 (`models.walk(".", …)`), 119-122 (`store.find`), 131-133 (`{top}/.cache/land-requests`), 212-219 and 281 (the locks under `{top}/.cache/work`); G4 (c0253.md:297), G10 (c0253.md:309); c0252 Interactions ("`<main checkout>/.cache/land-requests/<R-id>` (the main checkout is `git worktree list`'s first entry)").
Evidence:
- **(a) A supervisor started in a worktree.** `./zn work run` typed in `.worktree/R0010` gives `top` = that worktree. `requestWaits` then looks in the worktree's `.cache`, while the session's `done` writes the request into the main checkout's. The action line stays `done`, a session runs again, and two unchanged lines release the finished raft with `./zn stop`. `world.zn` also runs `.worktree/R0010/zn lander`: the branch's own engine with the person's credential, the self-landing c0252 G2 exists to prevent.
- **(b) Model files from the working tree.** `models.walk` reads `.models.toml` from the working tree. c0117's design review 002 F5 (quoted at `models.luau` 330-333) made the dispatcher read them "as tracked at a pinned commit … never from the working tree", and zz-arch rule 7 reads configuration that widens a guard from origin/main. A session can drop an untracked `.models.toml` into an item folder of `top` and raise its own `max_tokens`, `max_calls`, `stall_seconds` or `quota_wait_minutes`, or switch its CLI.
- **(c) Item facts from an unsynced tree.** `store.find` and `where` read the same working tree, and nothing in the loop fast-forwards it (c0249: `./zn next` "does not read this checkout"). An item captured after the last sync has no slug, so its worktree is `prep-c0300`. A lost raft whose move to `active/` is not in this tree reads as not active, so `stepFor` gives `status <R> preparing`, which refuses a readied raft.
- **(d) Locks per worktree.** G4 says "Two CLIs run as two checkouts". The per-item lock lives under each `top`, so two supervisors in two worktrees of one clone both take the same `rafting` pick, and no claim protects it.
Critique: the tempting fix is to hard-code the main checkout for the requests only. The engine, the settings, the item facts and the locks share the same root cause.
Consequences: resolving the main checkout means a supervisor started in a worktree either refuses or runs as if started in main. Reading the settings from origin/main needs `models.walkAt` at the `main` the turn fetched; `next` already fetches it, so it costs nothing new. Locks in the main checkout's `.cache` are shared by every worktree of the clone, so G4's "per checkout" becomes "per clone": say so. A main checkout someone edited is then F1's tripwire's to catch.
Recommendation:
- **Run in the main checkout only.** The supervisor resolves the main checkout (`git worktree list`'s first entry, as c0252 does) and refuses `work run` and `--detach` anywhere else ("the supervisor runs in the main checkout: <path>").
- **Read and write there.** It runs that checkout's `zn` and keeps the land requests, the locks and the state there.
- **Read settings from main.** It reads every `.models.toml` with `models.walkAt` at the fetched `main`, and `where` and the slug from origin/main (`git show`), never from the working tree.
- **Cases:**
  - command.spec refuses `work run` in a fixture worktree;
  - an untracked `.models.toml` in the fixture's main checkout changes nothing;
  - an item that exists only on the fixture's origin/main gets its slug.
- **Rules rows** with the mutants "reads the working tree's `.models.toml`" and "reads requests under `top`".
Lesson: zz-arch/guard-state-out-of-reach-or-checked

### F3 [high] "record spend" is a captured outcome with no design and no criterion, and the supervisor drops every session's measured row
Where: captured Problem ("run the item's next step in its own worktree with the model the file names, record spend, repeat"); Idea ("spend is recorded per step"); the Outcomes table (no row); AC1 to AC13 (none); prototype `workedge.luau` 195-210 (`modelstep.launch`'s result cut down to outcome, detail and session); `modelstep.luau` 8-9 ("The measured row (wall, CPU, tokens, the model id) is written by the caller from the result `launch` returns").
Evidence: `launch` returns each session's tokens (the adapter's count), wall time, CPU and model id, and workedge throws them away. The sessions' own `./zn spend` and `finish` rows cannot replace them: z-work step 9 says grok's and agent's rows have "no count on this row today". The headless sections say "Do not pass `--time` or `--tokens`: the dispatcher records the session's wall, CPU, tokens and model". Here the supervisor stands in for the dispatcher, and it records nothing. No case asserts a row.
Critique: a captured outcome without a design or a criterion (item 11). The tempting fix is to print the tokens in the log, but spend is a ledger row (zz-rules Spend) that lands with the item.
Consequences: where the row goes depends on the pick:
- **A raft:** into the raft worktree's measure buffer, folded by its next `./zn commit` as the code-review rows are, or held pending until the merge as the dispatcher's `deliver` row is.
- **A draft:** under `--phase design` on the prep branch.
- **A rafting pick:** on the rafting branch.

A session that ends on quota or crashes still spent tokens, so it gets a row too. For a resumed session, each session counts only its own usage. Check per CLI that the stream does not report the session's total since it began.
Recommendation: write one measured row per session the way the dispatcher does, reusing its row writer: wall, CPU, the adapter's tokens, the model id and the CLI, with the phase taken from the pick kind. Add an Outcomes row and a Checked criterion. In session.spec, assert that the fake claude's 123 tokens (input 100 + cache writes 20 + output 3) and `claude-opus-5-5` reach R0010's spend buffer for each of the two sessions. Rules row with the mutant "drops the row".

### F4 [high] G7 releases a raft with `./zn stop`, which does not mark it blocked: the raft stays claimable, the skip list then starves every other raft, and across runs the same raft is claimed and dropped forever
Where: G7 (c0253.md:303), The turn step 5 (c0253.md:273), AC4; prototype `workloop.luau` 105-117, 127-131, 249-252; c0250 outcome 3 and its docs.spec (`unsays(work, "run `./zn stop <R>`. Tell the person")`); c0252 Outcomes 1 and 6 (`landcheck.escalation`).
Evidence:
- **(a) Not a block.** The user: "Only if it is blocked would it let go, at which case it marks the raft blocked", and the capture's "It lets go only when blocked. Then it marks the raft blocked (c0250)". `./zn stop` moves the raft back to the backlog as `prepared`: it is claimable, it has no `escalation.md`, and the board shows no block. c0250 replaced exactly this: its docs.spec removes "run `./zn stop <R>`" from z-work step 5.
- **(b) The skip list starves the stack.** `next` prints the best-ranked claimable raft, which after the release is usually the same one. `workloop.run` sets `pick = nil` for a skipped id and idles. `next` prints that id every minute, so R0020, R0030 and the rest are never taken for the whole run: one release wedges the supervisor. loop.spec's fake `pick` answers "nothing claimable" after its list, so the wedge never shows.
- **(c) An endless cycle.** The next supervisor (another checkout, a restart, another host) reads the same raft, readies it, spends two sessions and stops it again, forever. Each cycle publishes a `ready` and a `stop` commit.
- **(d) The wrong give-back for issues.** For a draft or a rafting pick the release is `./zn stop <c-id>`. An issue claim is given back with `status <id> new` (zz-rules Claims), and a rafting pick holds no claim.
- **(e) Failures count as no progress.** Every outcome but quota does (`ranOn = line` for `failed`, `stalled` and `cap`). A missing agent token or an uninstalled CLI readies and stops two rafts, then stops the worker.
- **(f) G7's reasons are wrong.** "it has no model to write one" does not hold: c0252's dispatcher writes `escalation.md` from a pure function (`landcheck.escalation`) with no model. "the dispatcher's own rule for a stuck chain" does not hold either: the dispatcher stops the chain (exit 1) and waits for `retry`, and never gives a claim back.
Critique: the tempting fix, "skip it and ask `next` for the one after", has no `next` option to rely on. It also leaves the raft as claimable work for every other worker.
Consequences:
- **The reason.** Blocking needs a reason from c0250's closed list. Choose one (`design-gap`, or `red-gate` when a check failed) and say which.
- **The note.** It needs an `escalation.md` with the four sections and exactly one `(recommended)` option, written in the raft's worktree, and `./zn block` run there (c0250 refuses the main checkout).
- **Green layers below.** If layers below are green, c0250 Q1 ("They merge now") lands that prefix first (F6).
- **Failed starts** should never reach a claim.
Recommendation:
- **Block instead of release.** The supervisor writes `escalation.md` from a pure `supervise.escalation(...)`, as c0252 does: the Question; What was tried (the two action lines and the session outcomes); Open findings or error; Options, with `retry` recommended. It runs `./zn block <R> <reason>` in the raft's worktree, checks its exit status, and only then counts the raft blocked.
- **Issues.** A draft is blocked with `./zn block <id> <reason>` in its prep worktree (c0250 blocks a `preparing` issue). A rafting pick has nothing to give back.
- **Count only real no-progress.** A session counts as no progress only when it ended `ok`. A crash or a stall is retried once, then blocked with its outcome in the note.
- **Check before claiming.** Check the token, the CLI and the worktree before any claim.
- **Cases:**
  - after a no-progress block, the fake `next` prints R0010 and then R0020, and the loop takes R0020;
  - the block runs in the raft's worktree with a note `escalation.parse` accepts;
  - a first `failed` session is not counted.
- **Mutants:** "stop instead of block", "skip by idling" and "count failures as no progress".
- **AC4.** Reword it to match.
- **If no reason fits.** If none of c0250's six reasons fits a raft that moves nothing, escalate to the user: (a) use `design-gap`; (b) add a reason to c0250's list (a change to c0250, which the user approves again).

### F5 [high] Q9's quota path cannot block against c0250, never forgets an old outage, and reads "the raft's notes" that no one writes
Where: The turn step 7 (c0253.md:275), Interactions c0250 (c0253.md:281); prototype `workloop.luau` 190-199 (`world.zn({ "block", pick.id, "quota" })`, its result ignored), 83 and 194 (`allOutSince`); `supervise.quota` 258-297; the Idea ("The worker keeps those notes as it goes (where it is, what it learned, what is open)", idea review F30: fixed); Q9 ("continues on another CLI in a new session that reads the raft's notes").
Evidence:
- **(a) The block is refused and the refusal ignored.** c0250's `./zn block` refuses "the main checkout ('block runs where the note was written')" and "a note of the wrong shape". `world.zn` runs in `top`, the main checkout, and no `escalation.md` is written, so the real `block` is refused. The loop ignores the result, counts the raft blocked, skips it and stops beating. The raft stays `active`, claimed and parked by its PR (c0265: "a claim with an open pull request … is parked: never lost"): nobody holds it and nobody can take it over. loop.spec's fake `zn` answers yes to every command.
- **(b) An old outage blocks a new one.** `allOutSince` is set when every CLI is out and never cleared after a session succeeds. Say every CLI is out for an hour starting at T, the raft then works for a day, and then every CLI goes out again for a minute. `now - allOutSince >= cap` holds at once, and the raft blocks with `quota`.
- **(c) No notes.** The switched session gets the new-session prompt ("Read `z-nile/skills/z-run/SKILL.md` and follow it for R0010"). Nothing defines the raft's notes or tells a session to keep them, although the confirmed Idea says the worker keeps them and Q9 says the new session reads them. No criterion covers them.
Critique: (a) is the interface mismatch of F4; (b) is a missing edge case with a wrong result; (c) is a decided outcome without a design.
Consequences:
- **(a)** As in F4: the supervisor writes the note, blocks in the raft's worktree and checks the exit status, and c0250 Q1's prefix landing applies.
- **(b)** Resetting needs a rule for "stayed out": the cap counts one unbroken outage.
- **(c)** The notes need a place (a file in the raft folder on the layer, committed with `./zn commit`, or the issue's Verification log), a writer (the z-work headless branch, at each layer boundary and before a session ends) and a reader (the switched session's prompt names the file). A taker (c0274) reads the same file.
Recommendation:
- **Block as in F4,** with the reason `quota` and the outage's times under What was tried.
- **Clear the outage marks.** Clear `allOutSince` and the per-CLI `out` marks when a session ends `ok`.
- **Define the notes.** Define the notes file and its writer in the z-work headless branch, and name it in the switched prompt.
- **Cases:**
  - loop.spec: "a second outage after a working session waits the full cap again" (mutant: never reset);
  - the block case asserts the raft's worktree as its folder and a note that parses;
  - pure.spec: the switched prompt names the notes file;
  - docs.spec: the headless branch says to keep the notes.

### F6 [high] The landing path misreads c0252: the lander refuses while CI runs, so finished green rafts are stopped; a red gate still runs the lander; a game's gate runs twice; and the landing of green layers below a block is never served
Where: The turn step 6 (c0253.md:274), U1 (c0253.md:382), G5 (c0253.md:299), AC8; prototype `supervise.luau` 17 (`GATE_WAITS = 4 -- ./zn land-gate exit code: the checks are still running`), `workloop.luau` 132-164; c0252:
- Public surface: "`./zn land-gate <R-id>` (new; exit 0 passes, 4 waits, 1 red)";
- Outcome 5: "`./zn land-gate`: nothing for a tooling stack; for a game the clean clone, `--full` and `scripts/cicd` … exit 4 stops at the gate";
- G3: "No `~/.config/pickman/cicd.toml`, a held lease or a failed publish is a wait (exit 4)";
- Outcome 8: `lander` "refuses one with a problem (but `self-gating`, `cicd-missing`), runs `land-gate`, … runs `done`".

Also c0250 Q1 and its z-work step 5 ("land them first with `./zn done <R> --through <issue>`").
Evidence:
- **(a) Pending CI stops a green raft.** Pending CI is `land-check`'s `ci-pending` wait, not land-gate's exit 4. For a tooling stack land-gate does nothing and exits 0. So a tooling raft whose checks still run gets `lander`, which refuses (`ci-pending`). After a sleep, `lander` again, refused again. On the third turn `landTries > 2`, and the loop runs `./zn stop`: a finished, green raft is given back within about two minutes.
- **(b) A red gate still runs the lander.** `world.gate` exiting 1 (red) falls through to the `land` branch, which runs the lander anyway. c0252 treats `full-gate-red` as a redo: the worker runs again up to `merge_retries`, then blocks with `red-gate`. The supervisor stops the raft instead.
- **(c) A game's gate runs twice.** For a game stack the supervisor runs `./zn land-gate` (the clean clone's `--full`, then `scripts/cicd`, which publishes the CICD places), then `./zn lander`, whose own `land-gate` runs both again.
- **(d) The landing below a block is never served.** A session that blocks while layers below are green runs `./zn done <R> --through <issue>` under `ZN_HEADLESS`. c0252 then writes the request, and "the worker then stops". The next action line is the blocked layer's, not `done`, so `move` never looks at the request. The next session tries again, and then F4's release follows. c0252's G1 solves this only under `ZN_DISPATCH`. Under `ZN_HEADLESS` nobody lands those layers, against c0250 Q1's "They merge now".
- **(e) Steps, not time.** `LAND_WAIT_SECONDS` counts sleep steps (`landWaited += 60`), not wall time, and each `land-gate` of a game takes minutes.
- **(f) An unbounded wait.** A headless supervisor (`canLand` false) waits for a lander with no limit, holding the item lock and the claim.

U1 calls the lander's behaviour on pending checks "not determined", but c0252's prepared document determines it. loop.spec's fake `gate` returns 4 for "pending", which the real command never does.
Critique: the tempting fix maps exit 1 to a release as well. c0252 already sorts every problem into wait, redo or block, and `land-check --json` prints them.
Consequences: `./zn land-check <R> --json` becomes the one read:
- **wait:** wait (beat, plain sleep, bounded by wall time);
- **redo:** a session told the problems (c0252's rerun prompt), within `merge_retries` and `MERGE_RERUN_CAP`;
- **block:** F4's block, with c0252's `landcheck.escalation` and its reason;
- **no problem:** `lander`, which runs land-gate once.

A request with `through:` is served the same way, whatever the action line says. The headless wait needs a limit and a stated end.
Recommendation:
- **One read.** Replace `world.gate` with `land-check` and drive the three kinds by calling c0252's own `classify`, not by re-deriving it. Never run `land-gate` before `lander`.
- **Serve every request.** Before starting a session, serve any request that waits for the held raft, `through:` included.
- **Time-bounded waits.** Bound every wait by elapsed `world.now()`, and give the headless wait a limit.
- **Correct U1 and AC8.**
- **Cases:**
  - a tooling stack with `ci-pending` waits and lands once it clears (mutant: lander while pending);
  - `full-gate-red` reruns a session with the problems (mutant: lander anyway);
  - a game stack runs one `land-gate` (count the calls);
  - a `through:` request lands the layers below before the next session;
  - the land wait ends by wall time against a gate that takes 600 s per call.
- **Fakes** answer only c0252's documented codes.
Lesson: zz-test/stand-ins-answer-only-named-arguments, zz-test/count-calls-in-poll-loops

### F7 [high] c0274 refuses the supervisor's beat, nothing beats during a session, and a draft claimed from the main checkout makes the session's own claim fail
Where: AC7; The turn step 4 (c0253.md:272); Interactions c0265, c0274 and c0275 (c0253.md:282); prototype `workedge.luau` 254-256 (`zn({ "beat", id })` in `top`), `workloop.luau` 100-103; `supervise.stepFor` (`status <id> preparing` for draft and lost-prep picks). c0274 Design:
- "`ready` and `stop` run in the main checkout, which holds no work and remembers nothing";
- "`unheld` and no `--adopt` refuses with `beat: this checkout does not hold <id>'s claim`";
- "`--adopt --stamp S` (the dispatcher's form)".

c0275 Design: "The dispatcher (`dispatcher.claimBeat`, called around `runner.run` in `modelStep`): while a model step works the item … every interval one child, `<main>/zn run --time 60 -- <main>/zn beat <id> --adopt --stamp <S>`", and its background beater starts "not in the main checkout". z-design step 1, and c0274's z-design text: "a lost prep is taken over by `./zn status <id> preparing` run in the worktree you will work in".
Evidence:
- **(a) Every beat is refused.** Every `./zn beat R0010` the supervisor runs from the main checkout is `unheld` and refused. "A refused beat never stops the worker", so it never beats, silently, through every quota and lander wait.
- **(b) Nothing beats during a session.** The loop beats only between sessions. A z-run session follows z-work's loop until the raft ends (its prompt never says to stop after one action), so the turns are hours apart. c0275 built `claimBeat` for exactly this: a process that runs a model step for an item. The supervisor calls `launch` without it.
- **(c) A draft claim that loops.** A draft pick runs `status c0300 preparing` in the main checkout: no memory, and no beater (c0275). It then starts z-design in `prep-<slug>`, whose step 1 runs `status c0300 preparing` again. c0274 judges the live stamp and refuses ("claim alive"). Until a prep PR exists (c0265 parks only a claim with an open PR), nothing beats the claim. It reads lost after 15 minutes, and the next `lost` pick takes it over and starts the same refused z-design again, every quarter hour.

AC7's fake `beat` accepts every call.
Critique: the captured "It beats (c0265) every 5 minutes while it holds a raft" holds only against the fake.
Consequences: `--adopt --stamp S` needs the stamp the claim made, read from origin/main after `ready` or `status` (`heartbeat.stampIn`). A beat in a task beside `launch` needs the runner to yield; c0275 cites c0265's E3 that a `process.exec` in a task does. A `lost` answer from the beat means the claim was taken over: end the session and the item. Claiming a draft in the worktree the session works in means the supervisor makes that worktree first, and the prompt says the claim is made.
Recommendation:
- **The dispatcher's beat.** Beat in c0275's dispatcher form, in a task around every session and every wait (reuse `dispatcher.claimBeat`), and end the item when the beat reports the claim taken.
- **Claim where the work is.** Make draft and lost-prep claims in the worktree the session works in (`./zn worktree prep-<slug>`, then `status` there), and tell the session that its claim is made.
- **Cases:**
  - the fake `beat` refuses a bare `beat <id>` and accepts only `beat <id> --adopt --stamp <S>`;
  - a session that takes 1200 s on the fake clock gets at least three beats;
  - a draft's claim runs in `prep-<slug>`.
- **Mutants:** "bare beat" and "no beat during a session".

### F8 [high] Nobody merges the prep or rafting PRs the supervisor's sessions open, so a rafting pick repeats every turn and approved drafts never reach `main`
Where: The turn step 4 ("A non-carried pick (a draft, a rafting) runs one session"), Interactions c0249 (c0253.md:279), the Q1 re-ruling (c0253.md:238); prototype `workloop.luau` 211-213 (`ok` and not carried = `moved`), `supervise.prompt` ("Never merge a pull request"); zz-rules Dispatch, The chain (the dispatcher passes the `prep` and `raft` gates itself); c0249 `next` rule 3 ("a backlog issue with status `prepared`, `design: ready`, an `approval.md` on origin/main, in no raft").
Evidence:
- **A rafting pick repeats.** A rafting session runs z-raft, which ends at its rafting PR. The agent's token cannot merge that PR, and the prompt forbids it. The issue's `raft:` line changes only in that PR (zz-rules Rafting), so on origin/main the issue is still "in no raft", and the next `./zn next` prints the same `rafting` pick. The session ended `ok`, so the pick counted `moved` and is not skipped. The supervisor starts z-raft again, on the `raft` role, every turn: a second raft and a second PR, then a third.
- **Approved drafts never land.** A draft session opens its prep PR and stops for `./zn approve`. Once the person approves, the PR still has to merge before the issue is `prepared` with `approval.md` on origin/main, and nothing merges it. The re-ruled Q1 leaves the person "ideas, approvals and escalations" only. Under `./zn dispatch` these two gates are the dispatcher's (`auto_merge = ["prep", "raft"]`).
Critique: a wrong result with unbounded spend, and the re-ruling's "then rafts approved issues itself by the fixed policy" is not delivered.
Consequences: passing a gate with the person's credential means the dispatcher's gate checks: the head pinned, the tracker-state shape, `auto_merge` naming the gate, merge-tree with today's `main`, and the check after the merge. Reuse `dispatch.gate`; do not rewrite it. A pick whose PR is still open must not be taken again, whether `next` skips it or the supervisor checks.
Recommendation: after a draft or rafting session, the supervisor treats the PR as the gate it is.
- **Pass gates as the dispatcher does.** It passes the gate with `dispatch.gate`'s checks when `auto_merge` names it: a rafting PR at once, a prep PR only when `approval.md` from `./zn approve` is on its head.
- **Do not retake an open PR's pick.** Otherwise it leaves the PR and does not take that pick again while the PR is open.
- **Cases:**
  - a rafting pick whose PR is open is not run again, though the fake `next` keeps printing it (one session in all);
  - with `auto_merge = ["raft"]`, the fake gate merge is called once.
- **Rules row** with the mutant "counts the rafting pick moved and takes it again".
Lesson: z-design/results-land-on-every-path

### F9 [high] Command failures are read as answers: a failed `work next` becomes an action or abandons the raft, a failed `next` ends the waiting supervisor, and a crashed `next` reads as "nothing claimable"
Where: prototype `workedge.luau` 124-127 (`action` keeps `said` whatever the exit status), `supervise.parseAction` 212-221, `supervise.parsePick` 29-35, `workloop.luau` 118-126 (`hold` is counted blocked, with no release) and 245-248; z-work step 7 ("If the command you just ran fails for a reason that is not this raft (… fetch failed …), stop").
Evidence:
- **A failed `work next` becomes an action.** `world.action` returns the first line of stdout and stderr even when `./zn work next R0010` failed. An error such as "error: fetch failed: …" parses as the action `fetch`, and starts a resumed session told "The next action is: error: fetch failed …".
- **Or the raft is abandoned.** A Lune trace "main.luau:7790: …" matches nothing and reads as `none`, so `move` says `hold`. The item ends `blocked` with its claim kept: not released, not beaten, parked by its PR.
- **One network blip ends the wait.** `parsePick` turns any exit but 0, or 1 with nothing printed, into a problem that ends `workloop.run`. One network blip in a week of waiting for work ends the detached supervisor, against Q6's "until … it is stopped".
- **A crash idles forever.** A Lune error exits 1 with only stderr, which `parsePick` reads as "nothing claimable": a broken `next` leaves the supervisor idle and silent forever.
Critique: these are wrong results on common events (a fetch failure, a crash), and z-work's own step 7 already names the rule.
Consequences: telling "nothing" from a crash needs `next`'s answer to be distinct from Lune's own exit 1. That is c0249's interface: either rely on the stderr line it prints, or ask c0249 for its own exit code.
Recommendation:
- **Check every exit status.** Check the exit status of every `./zn` the loop reads. A failed read is a wait (beat, sleep, retry, say so in `status`), never an action or a release. After N failed reads in a row, stop and name the error.
- **Tell "nothing" from a crash** by c0249's stderr line or its own code.
- **Cases:**
  - `action` returning `(false, "fatal: …")` starts no session and keeps the item;
  - `pick` exiting 128 waits and retries;
  - exit 1 with a Lune trace on stderr is a failed read.
- **A mutant for each.**
Lesson: zz-arch/child-exit-status-counts

### F10 [high] G1's `z-work --here` keeps a worker that carries its context from raft to raft, against the captured "Context stays only within one raft" and Q8's "clearing is always a new session"
Where: G1 (c0253.md:235); the prototype z-work SKILL.md, "Which worker you are", second bullet; README "The worker", first paragraph (unchanged: "with none named it goes on to the next raft ready would accept, in the same context"); the capture's "A worker clears itself whenever a raft ends … Context stays only within one raft"; Q8.
Evidence: G1 says "`z-work --here` keeps #318's loop (the session itself takes the next raft and the one after)". z-work step 8 says why such a session cannot clear itself: "None of these CLIs gives you a command that clears the session … Carry on, and re-read." A person who types `--here` therefore gets a worker whose context crosses rafts, which is exactly what Q3 and Q8 chose the supervisor to remove. G1 also cites "The user has restated that the person's own session is the main way in" with no quote and no date, and no line on this issue records it.
Critique: both decisions can hold without the cross-raft loop. What #318 needs ("they stay in control, see progress in their own terminal and can ask the agent what it is doing") is met by a session that carries one raft and then stops.
Consequences: z-work step 6's "run `./zn work next` with no raft" changes for `--here`, and #318's `--released` count is no longer needed there.
Recommendation:
- **One raft, then stop.** `z-work --here` with no raft named takes the next raft, carries it, and stops at its end with `work.forRaft`'s own words ("Stop. Tell the person to start a fresh session (or /clear) and run z-work again"). The person's new session is the clearing.
- **Quote or drop the restatement.** Quote the user's restatement with its date, or drop the claim.
- **docs.spec pins:**
  - the `--here` branch says it stops after one raft;
  - the README's first "The worker" paragraph no longer says "in the same context".
- **The cross-raft loop needs the user.** If the user wants an in-session loop across rafts, that needs a Scope decision line. Escalate to the user: (a) one raft per session; (b) keep the loop and record that "Context stays only within one raft" does not hold for `--here`.

### F11 [high] The z-work entry points do not do what Q8 and Q12 decided: the window and terminal runs start no supervisor, the docs pin the false line, and "the same CLI" has no design
Where: G2 (c0253.md:293), G3 (c0253.md:295), AC9, AC12; the prototype z-work SKILL.md ("run `./zn run --time 3600 -- ./zn work` in the background"; "A person at a plain terminal runs `./zn work` there"); README ("or run `./zn work` (a supervisor: no model, …"), pinned by docs.spec; Q8 ("runs each raft in a new headless session of the same CLI"); Q12; `workedge.world` 95-97 (`--cli` checked against `supervise.RESUME`).
Evidence:
- **The window and terminal runs print the skill.** G3 and AC9 make a bare `./zn work` print the skill. G2's foreground run at a terminal and the skill's window run both use a bare `./zn work`, so both print the skill and end. Q12's second option does not exist as written, and the README line that docs.spec pins says the opposite of AC9.
- **The hour is not Q12's.** The window's one-hour cap comes from the AGENTS.md process rule, not from Q12's terms ("closing or clearing the CLI stops it"). A window supervisor that waits for work dies within the hour.
- **Not the same CLI.** On Q8's "of the same CLI": the skill runs `./zn work --detach` with no `--cli`, so a person in kimi gets sessions on whichever CLI the role names.
- **`--cli` for a CLI the role does not name.** `resolved.specs[X]` is nil, so every session fails, and F4's rule turns that into a release of every raft. `--cli agy` passes the check (`RESUME` has a row for it) though `models.CLIS` does not list it.
Consequences:
- **The model on that CLI.** "The same CLI" needs a rule for the model: the role's spec for that CLI (its `cli` or a fallback), else a refusal at start that names the role.
- **The window's lifetime.** Q12 accepted only "closing or clearing stops it"; an hour on top of that is a new limit, which is the user's call.
Recommendation:
- **Name the runs `./zn work run`.** The window and terminal runs say `./zn work run`, and the README line says `./zn work run` (G3's rule), pinned by docs.spec.
- **Pass the CLI.** The skill tells the session to pass `--cli <the CLI it runs in>`.
- **Refuse a bad `--cli` at start.** `work run` refuses at start a `--cli` that is not in `models.CLIS` or not among the role's tries, naming both.
- **The hour: escalate to the user.** Options:
  - (a) accept a one-hour window;
  - (b) let the window run unbounded in the background, stopped by SessionEnd and by `--session <pid>` as c0275's beater is;
  - (c) offer only the detached way (this narrows Q12, so it needs a Scope decision).
- **Cases:**
  - command.spec: `work run --cli kimi` with a role that names only claude is refused before any claim;
  - docs.spec pins `./zn work run` in both runs.
Lesson: z-design/instructions-runnable-where-they-run

### F12 [high] The workflow-picture rewording the 2026-11-08 scope decision asks for has no design and no criterion, and the README keeps a sentence G1 makes false
Where: Problem, "Scope decision (user, 2026-11-08) … and the workflow picture's `design` step, so that a worker drafts the design and a person approves it"; Outcomes row "the README's worker end"; AC12; docs.spec. In the README at 26265fa3a: lines 36-58 (line 41, `des["z-design: design, acceptance tests, review, approve"]`, inside "engineer end: any AI CLI, interactive"), and line 76 ("Today a person can run `z-work` … with none named it goes on to the next raft ready would accept, in the same context … *exists*").
Evidence: the worker-end text was reworded before this prep (README lines 79-85 already say "claims the first raft"), but the picture was not. Its design step belongs to the engineer and reads "design … approve", and no worker drafts. Neither the prototype nor AC12 touches it. After G1, the "Today …" paragraph describes `z-work --here`, not `z-work`.
Critique: a captured scope decision with no Design and no criterion (item 11).
Recommendation:
- **The picture.** The worker's loop gains the draft step ("no raft claimable: draft a confirmed idea's design"), and the engineer's design step becomes "approve the drafted design (`./zn approve`)".
- **The "Today" paragraph** says what `z-work`, `--here` and `/z-run` each do now.
- **Criteria.** Add both to the Outcomes table and to AC12. docs.spec pins a phrase of each, and that "in the same context" is gone from that paragraph.

### F13 [high] `Overrides: none` misses c0175's docs spec, and two of c0253's own doc pins are vacuous or duplicate a lower layer's pin
Where: Regression guard (c0253.md:387-389), E4 (c0253.md:379); docs.spec (`absent(r, "`kimi`, `agy`, `claude`, `grok`, `agent` or `deepseek`. *captured* (c0253)")` and `at(e, "One worker holds a raft and builds its layers in order")`); c0175 `acceptance/docs.spec.luau` 172-178 (it pins "`kimi`, `agy`, `claude`, `grok`, `agent` or `opencode` (DeepSeek and the other models it reaches). *captured* (c0253);"); c0175's guess "c0175 is expected to land first"; c0248 `acceptance/docs.spec.luau` 51 (it pins in zz-execute "One worker holds the raft and builds its layers one at a time, each complete before the next starts; a second machine works on the raft only through a takeover (c0274).").
Evidence:
- **The gate could not see it.** README text selects no spec (zz-test, Affected selection), so E6's affected gate could not see this.
- **c0175 first.** If c0175 lands first, as its own guess expects, its promoted spec pins "*captured* (c0253)". The prototype's README changes that label to "*exists* (c0253)" and turns the spec red: an override this chore must name.
- **The `absent` needle goes vacuous.** In that order c0253's `absent` needle (which says `deepseek`) can never match. AC12's "no longer calls the worker end captured" then passes with "*captured* (c0253)" still in place.
- **A paraphrase of c0248's pin.** c0248 already pins the one-worker sentence in zz-execute. c0253's paraphrase forces a second sentence that says the same thing.
Critique: an unnamed override is high (item 4), and a criterion a wrong change passes is high.
Recommendation:
- **Name the override.** Add `tests/acceptance/c0175/docs.spec.luau` to `Overrides:` for the order c0175-first; c0253 is a chore, so it narrows that pin in its own raft.
- **The other order.** Say in Interactions what happens if c0253 lands first: c0175's executor escalates.
- **Order-independent needles.** Make c0253's needles hold in either order, for example "*captured* (c0253)" absent from that README line.
- **Reuse c0248's sentence.** Pin c0248's sentence instead of a paraphrase.
- **Run the peers' specs.** Run c0175's and c0248's sequestered docs specs on the prototype stacked with their patches.
Lesson: z-design/peers-scans-run-on-the-prototype

### F14 [high] session.spec's guard case needs the real `claude` on the host and starts it if the guard regresses, and the guard does not resolve links
Where: session.spec, "AC6: a CLI the check cannot reach inside .cache is refused, never started" (`fs.removeFile(`{h.bin}/claude`)`); `fakecli.zn` (`PATH = {h.bin}:{process.env.PATH}`); prototype `workedge.luau` 166-183 (`command -v`, compared unresolved); `dispatcher.luau` 255-262 (`resolveBin`: `Cwd::realpath`); `c0117/dispatch-cli.spec.luau` 183-185 (`ln -s /bin/echo {h.bin}/agent`); the Rules row "reasoned: the mutant would start the user's real `claude`".
Evidence:
- **The case needs the host's claude.** With the fake removed, `command -v claude` falls through to the runner's `PATH`. The case expects "refusing to start", so it passes only on a machine with `claude` installed; anywhere else it reads "claude is not installed".
- **A regression starts the real CLI.** If `checking()` or the comparison regresses, the spec starts the person's real `claude -p … --permission-mode bypassPermissions`. zz-test lists this under Caught only by review ("Starting a model CLI"), and off macOS no network rule stops it.
- **Links get through.** The guard compares the unresolved `command -v` path with `.cache/`, so a link under `.cache` that points at a real CLI passes. The dispatcher's `resolveBin` resolves the link and refuses it.
- **The guard's mutant can be run safely.** c0117 tests the same rule with a harmless link to `/bin/echo`, which also makes the guard's mutant safe to run. The row's "reasoned" reason therefore does not hold.
Critique: item 9 (repository safety): a path from a spec to a real model CLI is high.
Recommendation:
- **Resolve, then compare.** Resolve with `Cwd::realpath` (move the dispatcher's `resolveBin` into the shared module of Implementation step 4) and compare the resolved path.
- **A harmless fake.** In the spec, replace the fake with `ln -s /bin/echo {h.bin}/claude` (it resolves outside `.cache` and does nothing) and assert "refusing to start".
- **A link case.** Add a case where a `.cache` link to `/bin/echo` is refused.
- **Run the mutant.** Run the guard's mutant and mark the row `run`.
Lesson: zz-arch/verify-the-value-you-use, z-design/reasoned-rows-claim-testable-reasons

### F15 [medium] A graceful stop, or a supervisor that dies, leaves a raft that is held and parked and never taken over
Where: The turn step 8 (c0253.md:276), AC3; prototype `workloop.luau` 93-99 ("with no beat it reads lost after 15 minutes and any worker may take it over (c0274)"); c0265 ("a claim with an open pull request, a dispatcher gate or a `questions.md` is parked: never lost"; "A layer's draft PR names its raft and ticket, which parks the claim").
Evidence:
- **Parked, never lost.** From `./zn start` on, a raft has a layer PR and is parked. It never reads lost, `next` never offers it, and the stopped supervisor never returns to it.
- **The message is wrong.** The message and the Design's sentence promise a takeover that c0265 rules out.
Consequences: resuming on restart needs the session id and item kept in the state file and checked against the claim on origin/main. c0274's "taken" answer means a takeover happened meanwhile: let it go.
Recommendation:
- **Resume first.** On start, before calling `next`, the supervisor resumes a raft this clone holds: its state file names the item and the session id, and it resumes that session.
- **Say how to resume.** `work stop` and `status` say which raft stays held and how to resume it (`./zn work run`, or `./zn work <R>` in a session).
- **Correct the text.** Correct the message and the Design's sentence.
- **Case:** a stop mid-raft, then a new run with nothing else claimable, resumes R0010 under the old session id (mutant: `next` first).

### F16 [medium] Nothing limits who may start a detached supervisor, and the reaper exempts any process whose arguments say `work run`, with everything below it
Where: Chore checklist "Guards" (c0253.md:322); prototype `reap.luau` (`isSupervisor`, `underSupervisor`, and `reap.decide` skipping before every rule), `workedge.detach`; AGENTS.md, Processes; zz-test, Bounded commands (the reaper paragraph's list of what is never reaped).
Evidence:
- **Nested supervisors.** `./zn work --detach` is not refused under `ZN_HEADLESS` or `ZN_DISPATCH`, or inside a check run. A headless session reading the z-work skill's first branch ("`z-work` with no raft … Run `./zn work --detach`") starts a nested supervisor in its own worktree. That supervisor has its own `top` and lock, holds the agent's token, is immune to the reaper, and takes more rafts.
- **Matched by text.** `isSupervisor` matches the text "engine/main -- work run" in any checkout or fixture.
- **Every rule skipped.** `underSupervisor` skips every rule for the whole tree below, the deadline rule (`ZN_BOUNDED_DEADLINE` passed) included.
- **No lifetime bound.** There is none (`MAX_TURNS` × 60 s is about two years).
- **The docs still promise the reaper.** AGENTS.md's "`./zn reap` stops what still leaks" and zz-test's reaper paragraph do not name the new exemption.
Recommendation:
- **Refuse where it must not start.** Refuse `work run` and `--detach` under `ZN_HEADLESS`, under `ZN_DISPATCH`, inside a check run, and outside the main checkout (F2).
- **Exempt one process, from one rule.** Exempt from the orphan rule only the process the main checkout's `.cache/work/state` names (its pid and start id). Keep the deadline rule for everything below it.
- **Restate the rules.** Add the exemption to zz-test's reaper paragraph and to AGENTS.md's Processes paragraph.
- **Order the skill.** Put the headless branch first under "Which worker you are".
- **Cases:**
  - command.spec: `ZN_HEADLESS=1 ./zn work --detach` is refused;
  - reap.spec: a "work run" process that the state file does not name is not exempt;
  - reap.spec: a marked process below the supervisor, past its deadline, is still reaped.
Lesson: z-design/most-specific-environment-first

### F17 [medium] The starter's session markers flow into every session
Where: prototype `workedge.luau` 185 (`table.clone(process.env)`, then the runner's environment overlay); `supervise.stepEnv`; AC6 ("`ZN_DISPATCH` not"); c0250's `escalation.md` header `Session:`, and its `resolve` "Refused when the running CLI session is the note's `Session:`".
Evidence:
- **The person's environment is passed on.** The detached supervisor inherits the person's CLI environment (`CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`, `KIMI_SESSION_ID`, `AI_AGENT`, and `ZN_DISPATCH` when it ran under one) and hands it to every session.
- **Spend counts the wrong transcript.** A grok or agent session's `./zn finish` or `done` then counts the person's claude transcript (`sessionread` reads `CLAUDE_CODE_SESSION_ID`).
- **The block names the wrong session.** Its `./zn block` writes the person's session id under `Session:`, so the person's own agent is refused when it resolves that block on the user's word.
- **AC6 is not met.** `stepEnv` does not unset `ZN_DISPATCH`, against AC6.
Recommendation: `stepEnv` clears the agent markers and session ids (the lesson's list), `ZN_DISPATCH` and `ZN_DISPATCH_DIR`. pure.spec feeds a base holding each and asserts them gone (mutant: keep `CLAUDE_CODE_SESSION_ID`).
Lesson: zz-test/terminal-fixtures-clear-the-agent-session

### F18 [medium] G6's cost leaves out that the c0305 edge holds the whole R-vision stack
Where: G6 (c0253.md:301), G12 (c0253.md:313), `depends_on`; Q11 ("it starts only when every member's outside dependency is done"); c0305 (`status: new`, `design: draft`; this design's Interactions: "Not designed (its idea review's F1 waits for the user)"); commit 6ead1904d (the user withdrew c0261, "the rest is c0305, c0306 and c0307", and c0253's edge moved from c0261 to c0305).
Evidence:
- **The edge stops the stack.** G6 calls the edge "only an ordering edge", costing "that function". Under Q11, though, an edge to an undesigned issue keeps R-vision (c0248 to c0254) from starting at all until c0305 is designed, approved and done.
- **G12 misstates the list.** G12 says the list "stays as captured". It is the captured list with c0261 replaced by c0305 (#325), which the user's withdrawal moved there for the "It is cheap" outcome.
Recommendation:
- **State the cost** in G6.
- **Put the choice to the user** in the approval session:
  - (a) keep the edge, so R-vision waits for c0305;
  - (b) record that c0253 does not consume c0305, and drop the edge with a Decided line;
  - (c) move the edge to c0254.
- **Correct G12's wording.**

### F19 [medium] A resumed session is not told its skill, so a CLI that quietly starts a fresh session works with no instructions
Where: `supervise.prompt` 127-152 (the resumed prompt is "Continue R0010. The next action is: …", with no skill path); E1 (grok's `-s`: "not proven by help"); The turn step 4.
Evidence: E1's fallback assumes that a failed resume fails loudly. If `grok -s <existing id>`, or any CLI after an upgrade, starts a new session instead, that session gets no skill path and only two rules. It then guesses at "the next action", with auto-approve on.
Recommendation:
- **Name the skill in every prompt.** Every prompt names the skill's path and the raft; the resumed one adds "you have read it; continue".
- **Case:** pure.spec asserts the skill path in the resumed prompt (mutant: drop it).
- **Probe grok's resume.** Probe it in prep with two one-word calls, or say why not.
Lesson: z-design/probe-free-cli-lines-in-prep

### F20 [medium] loop.spec's fake World says yes to every command, so the interface defects above pass, and the Rules table lists none of their mutants
Where: loop.spec `fake`:
- `zn` returns `true, ""` for every command;
- `pick` answers nothing claimable after its list;
- `gate` returns any code;
- `beat` accepts any call.

Also the Rules and mutants table.
Evidence: F4 to F9 each pass AC1 to AC8, because the fake accepts:
- a `block` run in the main checkout;
- a bare `beat`;
- a `stop` of an issue;
- a lander while CI is pending.

It also never prints a released pick again while another raft waits. Rows the table lacks:
- a refused block is not counted;
- `allOutSince` is reset;
- a red gate runs no lander;
- a failed read starts no session;
- after a release the next raft is taken;
- a rafting pick with an open PR is not run again;
- every session writes a spend row;
- `z-nile/bin` is first on `PATH`.
Recommendation: make the fake World answer only the commands and arguments the design names, with each lower layer's documented refusals and exit codes (c0250's `block`, c0252's `land-check` and `lander`, c0274's `beat`). Add the rows above with their mutants.
Lesson: zz-test/stand-ins-answer-only-named-arguments

### F21 [low] `--detach` forwards the flags from a map, so "in order" does not hold
Where: prototype `main.luau` 7811-7819 (`for k, v in opts`); AC10 ("keeps every other flag in order"); pure.spec's detach case feeds `detachArgv` a list, so it never sees the map.
Evidence: Luau gives no order for a hash table's keys, so `--cli claude --max-items 2` may be forwarded as `--max-items 2 --cli claude`. That is harmless today, but the criterion promises the order.
Recommendation: build the forwarded list from the command's own arguments in order, or drop "in order" from AC10. command.spec: a `--detach` run with two flags logs them in order.

### F22 [low] The detached supervisor runs under `ZN_ENGINE_CPU` (1800 s), which nothing says
Where: `zn` (on the main path, `zn_lower_cpu "$lim"` before `exec lune run`); `workedge.detach` (it starts `{top}/zn work run`).
Evidence: a supervisor meant to wait for work for weeks is killed by SIGXCPU once its own CPU time reaches 1800 s. `status` then shows "dead (stale state file)", with no reason. Every session it starts inherits the same per-process limit, as dispatched steps do.
Recommendation: state the limit in the Design and the README, or start the supervisor with its own documented `ZN_ENGINE_CPU`. Have `status` say "ended without a summary (see the log)" when the log has no summary.

## Lesson candidates (for the lead; no lesson files written)
- **z-design: a new starter of model sessions owns every duty of the dispatcher's model step.**
  - Rule: when a design starts a model CLI anywhere but inside `./zn dispatch`, it lists what the dispatcher does around `runner.run` and says how the new starter does each.
  - The duties: the wrapper first on `PATH`, `ZN_REAL_*`, the agent credential, the publish broker, the tripwire's snapshot and `vetMain`, the measured spend row, `claimBeat`, `.models.toml` read at `main`, the gate merges, and clearing the step's environment.
  - Why: c0253's supervisor called `modelstep.launch` bare and lost all of them (F1, F2, F3, F7, F8, F17).
  - Check: for each duty of `dispatcher.modelStep`, does the design name where the new starter does it and the case that proves it?
- **z-design: an "unknown" about a prepared layer is answered from its document first.**
  - Rule: before marking an exit code, refusal or file of a lower layer "not determined", read that layer's Public surface and Interactions, and quote the meaning the design acts on.
  - Why: c0253's U1 called the lander's behaviour on pending checks undetermined, and mapped land-gate's exit 4 to "checks pending", against c0252's prepared text (F6).
  - Check: does every lower-layer code the design branches on carry a quote from that layer's document, and does the fake return exactly those codes?
- **zz-arch: a give-back that is not a block puts the item back on offer.**
  - Rule: when a loop lets go of an item, say what tracker state it leaves, what `next` prints next, and whether a skip list starves the items behind it.
  - Why: `./zn stop` left the raft claimable, and the skip list idled the supervisor while other rafts waited (F4).
  - Check: after the loop lets go of the first item `next` prints, does a case show the loop taking the second?
- **z-design: claims are made where the work is.**
  - Rule: a claim made for another session (by a supervisor or a dispatcher) is made in the worktree that session works in, or is beaten with `--adopt --stamp`, because c0274 keeps the claim's memory per worktree and the main checkout remembers nothing.
  - Why: the supervisor's beats from the main checkout were refused, and its draft claim made the session's own claim step fail (F7).
  - Check: for each claim the design makes, which checkout remembers its stamp, and does the session's skill claim it again?

Verdict: changes
