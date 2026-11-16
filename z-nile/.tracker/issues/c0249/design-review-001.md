# Review 001: c0249 (design mode)
Model: claude-opus-5-5
Effort: default (the launcher's setting)
Inputs: prep worktree `prep-issue-rank-order` at 5ca319f4e with the uncommitted c0249 files (`c0249.md`, `check.sh`, `acceptance/{rank,command,board,hash,app,docs}.spec.luau`, `acceptance/app.test.mjs`, `experiments/{prototype.patch,mutation-results.txt,mutate.py.txt,E3-plan.luau.txt}`); `./zn capture c0249` (capture 0e91b4d75); prototype `proto-c0249` at db70cadf5 against base f85c0c3a6 (`git diff f85c0c3a6 proto-c0249`); c0265's layers `origin/R0100/{1..5}` (c0276's `board.withVerdicts` at 6f31f21c9); c0263's `origin/R0099/1/c0263`; c0257's `origin/prep-omarchy-board-app`; the documents and sequestered specs of c0248, c0250 (`acceptance/work-board.spec.luau`), c0253, c0260 and c0276; promoted `c0053/publish.spec`, `c0060/retrofit.spec`; `./zn check c0249` (run here: 0/10, each failing for the reason E4 gives).

Probes (each through `./zn run --time`, on a scratch copy of the prototype's `z-nile/engine` under the session scratchpad, writing nothing in the repository):
- P1, the merge: a scratch repository whose `main` inserts `rank: 10` just before `status:` and whose branch edits `design:` and `status:` (as every prep does) merges with a CONFLICT; the same rank written right after `id:` merges cleanly.
- P2, an unrelated drag: issues c0050 (in R0002), c0100 (in R0001), c0200 and c0300, all unset; `rank.next` picks R0001. `rank.plan(…, "c0300", "before", "c0200")` renumbers c0050→10, c0100→20, c0300→30, and `rank.next` then picks R0002.
- P3, the app's drop at the end: on a stack of 194 unset backlog issues (E3's count of today's tracker), `rank.plan(…, "last")` returns 194 changes, for the first card and for the 10th. Card 150 dropped before card 120 returns 120 changes.

Scope fidelity (item 11): the capture carries no marker. The title, Problem, Non-goals and Solution match it, with the decision lines added since. Every captured outcome has a row in the design's outcome table. F1 is the one outcome left partly true.

The eleven guesses, judged: 1 (`last`, `before`, `--before`), 3 (the `ranked` row in the same commit), 4 (`next` exits 1), 7 (1 to 999999, gap 10), 9 (the app reads `effectiveRank`), 10 (`mayDraft` is z-design's claim gate) and 11 (`next` is read-only and may run in the main checkout) are sound, and their costs are honest. 2 is F2 and F5. 5 and 6 are F11. 8 is F1.

### F1 [high] `./zn list` never shows lost work first, against the confirmed Idea and the user's "Lost work first"; Guess 8's cost is wrong on both counts it gives
Where: c0249.md:237 (`list` "does not know lost work"), :238 and :281 (c0276 "hands its verdict ids to this order"), :267 (Guess 8); prototype `main.luau:3482`; `command.spec.luau:337-341`; prototype README line 92.
Evidence: The user (2026-11-07) says lost work comes before anything not yet started, whatever its rank. The capture says "`./zn list` and the board show the stack in order". The confirmed Idea (c0249.md:135; idea review F25, "both captured lines hold") says list and the board show "blocked items first, … then the order `next` uses", and that order puts lost work first. The design drops lost-first from `list` with no owner and no decision line. It does worse than leave it out: an active item counts as unset, so a lost raft prints after every ranked backlog item, and `command.spec` pins exactly that ("with no filter an active or done item counts as unset: after every ranked backlog item"). Guess 8's cost says "a stale claim shows in its rank place on `list` … until c0276 lands". That is false twice. An active claim shows at the bottom, not in its rank place. And c0276 is layer 4 of R0100, which lands with c0265, so before c0249; nothing then ever changes `list`. The new README line says "`./zn list` and the board show blocked items first, then the stack in order", directly under "Lost work comes first". A reader takes that to mean `list` shows lost work first, and it does not. The board's half is real but misquoted. c0276's code (`board.withVerdicts`, called in `board.build` after `collect`) moves lost cards first inside each band and bucket with a stable sort, and keeps the bands in order. It does not call `rank.order`. The two orders compose, but the design never says so and nothing tests it.
Critique: This is a prep choice that leaves a captured, confirmed outcome partly true, with no `Decided with the user` line. The tempting fix is a sentence in Non-goals, and that is a cut only the user may make.
Consequences: If `list` reads lost work, it becomes a network command: a fetch of the heartbeat branches, plus `gh` for stale claims, roughly E2's 12 s on a loaded machine. It also needs the degraded paths `next` has: offline, in a protected checkout, unreadable heartbeats. Either answer changes the README line and AC5.
Recommendation: escalate to the user: (a) `list` reads lost work as `./zn lost` does and orders blocked items, then lost (the heartbeat's order), then the stack. Offline or in a protected checkout it says so on stderr and lists without lost work (unknown is never lost). Cost: a slower, networked `list`. Add a command.spec case, "list puts a lost claim first, whatever its rank", using the fixture's stale c0013 claim at `ZN_NOW = LATE`, and a Rules row (mutant: no lost ids passed). (b) `list` stays offline, with a `Decided with the user` line that lost-first lives in `next`, `lost`, `status` and the board. Under (b), rewrite the README line so it doesn't claim `list` shows lost work first. Under either, correct :238, :267 and :281 to describe c0276's actual in-band rule. Then add a board case that builds with a lost verdict over ranked cards and expects lost first in its band and the rest in rank order. That case runs on a tree with c0276's layer, which will be on main when c0249 runs.
Lesson: z-design/never-narrow-captured-scope; z-design/quote-other-preps-before-promising

### F2 [high] Dragging an issue that belongs to no raft reorders the rafts and changes the raft `next` and `work next` take
Where: prototype `rank.luau:483-505` (the renumbering), `:197-211` (`rank.effective`); c0249.md:215, :218 (Guess 2), :210 (A raft's rank).
Evidence: Probe P2. With every item unset, the rafts sort by raft number, and `next` prints R0001. A person drags c0300, which is in no raft, above c0200 in the New column (`--before c0200`). The renumbering ranks every issue from the top through c0300, including c0050 and c0100, which are members of R0002 and R0001. Q5 says an unset raft takes its members' best rank, so R0002 jumps to 10 and R0001 to 20, and `next` now prints R0002. The board's raft bands and `work next` change the same way. The person never ranked a raft or a member of one. No spec pins that an unrelated move leaves the raft order alone.
Critique: Q5's "takes its members' best rank" assumes ranks a person gave. The renumbering writes ranks nobody chose, and through Q5 they decide which raft a worker takes next. The tempting fix is to skip raft members when renumbering. That breaks the issue order the move promises, because an unset member above the moved card would drop below it.
Consequences: Every fix changes what Q5 means in practice. Freezing the rafts gives them own ranks, and they then stop following their members. Counting only person-set member ranks makes the order read `provenance.md`. Each choice adds files or reads per drag.
Recommendation: put the choice to the user (it changes how Q5 reads), with the options: (a) a renumbering also gives every raft with no own rank, whose effective rank would change, an own rank that keeps its current place in the raft stack, in the same commit, each with a `ranked` row carrying `moved=<id>`. Cost: those rafts no longer follow their members. (b) A raft's effective rank counts only member ranks a person set directly: the member's own latest `ranked` row has no `moved=`. Cost: the order reads `provenance.md`. (c) Accept it, and say in the README and zz-rules that a drag among unset issues can reorder the rafts. Whichever is chosen, add rank.spec "an issue move never changes the raft order unless it moves a member", with P2's facts, and a command.spec case: `next` prints the same raft before and after an unrelated drag. Add a Rules row whose mutant is today's code.

### F3 [high] `rank:` written just before `status:` conflicts with every prep branch, and the stated fix ("keep both lines") needs a person, while the re-ruled Q1 makes drafting unattended
Where: c0249.md:185 ("written by `./zn rank` just before `status:`"), :258 (Merges); prototype `rank.luau:81-90`; `rank.spec.luau:101-113`; `command.spec.luau:171`.
Evidence: Probe P1. A prep branch always edits `status:`: `./zn status <id> prepared` is carried, so it edits the local document (z-design step 5). A rank published meanwhile inserts a line right above that `status:` line. Git treats adjacent edits as one conflict, so the prep's final sync, or its PR on GitHub, conflicts. The renumbering of F5 writes rank lines across the whole issue stack, so one drag in the New column can rank every issue being prepped above the drop point. Under the 2026-11-13 Q1 those preps are drafted unattended. `mergeOrigin` aborts, the dispatcher's merge fails, and the chain stops until a person resolves it. Written right after `id:`, the line merges cleanly (P1). Nothing rewrites `id:` or `type:` on a branch.
Critique: The design saw the conflict and accepted it, but a conflict-free spot exists. The lesson says to state a conflict only when no free spot does.
Consequences: AC1's text ("just before `status:`"), the rank.spec AC1 cases, `command.spec:171` (`"\nrank: 5\nstatus: "`) and mutant P6 change. `raftplan.designHash` and the publisher match the line by key, not by position, so they don't change. Place c0250's `blocked:` key and c0248's `layers:` line so they don't sit beside each other where both are written on branches. Both are published from origin, so that is fine.
Recommendation: `rank.withRank` writes the line right after `id:` (at the top of the block when there is no `id:`). Update AC1, the rank.spec AC1 expectations and P6 (mutant: insert last). Add a command.spec case: in the worktree, edit the issue's `design:` and `status:` and commit (as a prep does), publish a rank from the main checkout, then `./zn sync` in the worktree succeeds, with both edits present. Rules row: mutant = insert before `status:`.
Lesson: z-design/new-lines-sit-beside-lines-nothing-rewrites

### F4 [high] c0249's `list` order contradicts c0250's prepared spec: whichever lands second turns the other red
Where: c0249.md:237, :278; AC5 (:466); `command.spec.luau:326-341` (line 335: an unblocked raft before the blocked c0030); `z-nile/.tracker/issues/c0250/acceptance/work-board.spec.luau:272-310`; c0250.md:301.
Evidence: c0250 (prepared, the next layer of R-vision) pins `./zn list` as `R0020 c0020 c0040 R0010 c0010 c0030 c0050`. That is every blocked item first across both kinds (the blocked raft, then the blocked issues), then the rest as `list` prints today, rafts then issues. c0249 prints rafts first, then issues, with blocked items first inside each kind, so the same fixture gives `R0020 R0010 c0020 c0040 c0010 c0030 c0050`. c0249's AC5 case also asserts that the unblocked raft R0201 prints before the blocked issue c0030, which is the opposite of c0250's rule. When c0249 lands first, its promoted command.spec forbids the order c0250's sequestered spec requires. Promoted specs are never edited, so c0250's executor can't pass both. The design's c0250 paragraph (:278) speaks only of the board, and never searched c0250's specs for `list`.
Critique: Two prepared designs define one command's output differently, and neither names an override.
Consequences: Matching c0250 means `list` needs a pass across both kinds, blocked facts first. `rank.order`'s `blockedFirst` sorts one kind at a time. On the board, c0250 gives blocked cards a column of their own, so nothing there changes.
Recommendation: adopt c0250's shape, the one already pinned and decided ("Blocked column first", c0250's prep decision of 2026-11-13). `list` prints every blocked item first (rafts, then issues), then the rafts in stack order, then the issues in stack order. Change AC5's wording and command.spec:333-335 to pin it: a blocked issue before an unblocked raft. Run c0250's work-board `list` case on the prototype merged with c0250's prototype. If c0249 keeps its own shape instead, c0250's spec must change. That is c0250's owner's decision, recorded in both documents with the landing order.
Lesson: z-design/quote-other-preps-before-promising

### F5 [medium] Guess 2's cost is understated: the app's drop at the end of a column ranks the whole backlog in one commit, and OC1 does that on the real repository
Where: c0249.md:218 (Guess 2: "several files"), :291 (Scalability: "at most the backlog, about 10 files today"), :332 (E3), :477 (OC1, "Drag it to the end of the column"); prototype `main.luau:6971` onward (the build reads with `read(p)`).
Evidence: Probe P3. The app's drop below the last card sends `--before ""`, which plans `last`. With today's 194 unset backlog issues, that is 194 changed documents plus 194 `provenance.md` rows: 388 files in one commit. Dropping card 150 before card 120 writes 120 of each. E3 measured three moves and never `last`, which is the shipped hook's end-of-column case. The renumbering runs across columns and projects, so a drag in pickman's New column also ranks z-nile's prepared and preparing issues (F3's conflicts, F2's raft reorder). OC1, run as written on the real checkout, ranks every backlog issue as a side effect of an Observed step. `cmd.rank`'s build also reads every backlog and active document with its own `git show`, about 250 processes per publish attempt, up to 5 attempts, and nobody measured it. E2 timed `next`, which uses `cat-file --batch`.
Critique: The user can't veto a cost they were told is "several files".
Consequences: Each option for what an end-of-column drop means changes what the app shows after the drop, and the notice the app gives.
Recommendation: Rerun E3 with `last` and with a drop in the middle of a column, and record files per commit. Restate Guess 2's cost and the Scalability line. Put the drop's meaning to the user, since it is the gesture they asked for: (a) rank everything above it, as now; (b) a drop below unset cards unsets the moved card, so it sorts among the unset cards by number, and the notice says so; (c) refuse, naming how many items the move would rank. Run OC1 against a clone with a local bare origin, not the real checkout. Read the documents with one `cat-file --batch`, as `workread.facts` does.

### F6 [medium] Under the re-ruled Q1 a worker rafts approved issues itself, but `./zn next` has no place for that, and c0253 takes only what `next` prints
Where: c0249.md:41 (the 2026-11-13 re-ruling), :182, :229-233 (the pick: lost, raft, draft); c0253.md:17 ("loop: `./zn next`, claim, run the item's next step"), :69 (Non-goal: "The order `./zn next` prints … c0249").
Evidence: The re-ruling recorded on this issue reads: the worker "drafts designs and stops at your `./zn approve`, then rafts approved issues itself by the fixed policy". The design takes only "z-raft does not ask" from it. `next` prints lost work, a claimable raft or an issue to draft. A prepared, approved issue in no raft is never offered, and no person rafts any more. c0253's loop runs `next` and leaves the order to c0249, so approved issues pile up unrafted, no raft becomes claimable, and the loop keeps drafting.
Critique: "The next claimable item" now covers rafting as well as drafting, and neither this design nor c0253 says where rafting sits.
Consequences: Where rafting goes (before drafts, after them, or outside `next`) is a product choice. A new pick kind also changes the line c0253 parses.
Recommendation: Either add a pick, e.g. `<id> raft approved, in no raft` (printing the issue `./zn raft-plan --apply` would group first), placed where the user rules. The re-ruling's own sequence, "drafts … then rafts approved issues", is the default to put to them. Add rank.spec and command.spec cases and a Rules row. Or record in Interactions, and in c0253's documents through its owner, that c0253's loop runs `./zn raft-plan --apply` whenever `next` offers no raft.

### F7 [medium] The board's issue and raft list views still sort by id, so the board shows the stack in order only in its columns
Where: prototype `board.luau:1058-1063` (`table.sort(views.rafts.ready)` and the other five buckets); `board.html:178, 239` (the page draws `model.views[view][g]` in model order); c0249.md:238; AC5.
Evidence: c0249 orders the columns' bands and cards. The Rafts and Issues views still `table.sort` each bucket by id text, so `c…` comes before `d…` before `f…`. The Ready bucket of rafts, the very list `next` and `work next` choose from, is shown in a different order from the one they use. board.spec checks only `columns`.
Critique: "The board shows the stack in order" is met for one view of the page.
Consequences: c0276's `withVerdicts` reorders these buckets afterwards with a stable sort (lost first), so it composes with a rank order.
Recommendation: Order each bucket with `rank.order` over the model's facts (`blockedFirst`). Add a board.spec case asserting the rafts' and issues' buckets in rank order with the existing fixture (R0003 at 5, R0002 at 20, R0001 at 50), and a Rules row whose mutant keeps `table.sort` on the bucket.

### F8 [medium] Rules the design states with no Rules row and no case, each with a plausible mutant that survives
Where: Rules and mutants table; c0249.md:222-226, :230, :241, :275; `command.spec.luau`, `hash.spec.luau`.
Evidence:
(a) "Two people ranking at once: `publish.commit` re-runs the build on a lost race, so the second plan is made from the first's result" (:275). No spec races. A mutant that computes the plan once, before `publish.commit`, and returns it from the closure passes every case.
(b) `next` "reads origin/main". Every main-checkout `rank` in command.spec fast-forwards first, so a `workread.facts` that read `HEAD` would pass.
(c) "When the heartbeats or the pull requests cannot be read it says so … unknown is never lost. In a protected checkout it reads no remote" (:230): no case.
(d) The publisher's refusal on a `retired/` document: hash.spec covers active and done only.
(e) "It runs over every item document in every state" (:241): no malformed rank on a done item.
(f) An off-main main checkout is refused: AC2 lists only dirty.
Critique: z-design asks for a row for every behavioural rule. Item (a) is the one that keeps two concurrent drags right.
Consequences: A race case needs a `pre-push` hook in the publishing checkout, as `c0053/publish.spec:374` does. The hook must unset `GIT_DIR`, so the promoted spec needs an entry in `tests/tooling/repo-fence.spec.luau`'s `ALLOWED`, which review checks.
Recommendation:
(a) A command.spec case with that hook publishing a competing rank on the first push. Assert that the final ranks derive from the competitor's result, in two commits. Rules row: mutant = plan outside the build. Alternatively, move the build into a pure `rank.changes(paths, read, …)` in `rank.luau` (zz-arch rule 4) and give rank.spec a case calling it with two different reads.
(b) Publish a rank from the worktree, then `next` in the unsynced main checkout must see it. Mutant: read `HEAD`.
(c) A `gh` fake that fails and missing heartbeat refs: `next` names the failure on stderr and picks the raft. Mutant: ignore `beatsError`.
(d) A hash.spec case with a `rafts/retired/` document.
(e) Add a done item with a malformed rank to command.spec AC6.
(f) Add an off-main main checkout to the refused case.

### F9 [medium] hash.spec runs raw git with computed arguments instead of `@tests/lib/fixture`
Where: `hash.spec.luau:23-33` (`git(cwd, args)` over `process.exec("git", args, { cwd = cwd })`), :86-108 (`config`, `add -A`, `commit`, `clone`, `show`, `rev-parse`).
Evidence: zz-test: "Run git and `./zn` in a fixture only through `@tests/lib/fixture` … Raw git only for `rev-parse`, `ls-files`, and `init` or `clone` to a named path." `c0060/retrofit.spec` calls "raw git with computed arguments" a violation. Its list is fixed, so the gate won't catch this spec. board.spec, in this same issue, does it right. The fixture is under `.cache/c0249-hash` with its own repository and an `@example.invalid` identity, so the jail and the fence hold. But the helper's refusal is the layer that catches a fixture whose `.git` is missing, and this spec skips it.
Critique: Specs are sequestered after prep, so this has to be fixed now.
Consequences: none.
Recommendation: Use `fixture.git` for `config`, `add`, `commit`, `show` and `rev-parse` in the fixture, and keep raw git only for `init` and `clone` to named paths, as board.spec does.

### F10 [low] Restated rules: AGENTS.md's list of what may edit the main checkout, and a README hunk that regresses c0265's label
Where: c0249.md:261 ("`AGENTS.md` restates none of it"); AGENTS.md ("the main checkout is never edited, except by `./zn` itself (`ready`, `stop`, `sync`, and the board refresh …)"); prototype README line 90 (`*exists* (c0265)` becomes `*designed* (c0265)`).
Evidence: `rank` now fast-forwards the main checkout, as `ready` and `stop` do, and AGENTS.md lists those by name. The prototype's README hunk turns c0265's Order label back to *designed*. Once R0100 lands it is *exists*, and docs.spec checks only c0249's own row.
Critique: Two documents will say something false the day this lands.
Consequences: none.
Recommendation: Add `rank` to AGENTS.md's list and a docs.spec phrase for it. Leave c0265's label as main has it, and drop that hunk from the patch.
Lesson: z-design/restated-rules-move-together

### F11 [low] Two guesses' texts: Guess 6 cites a replaced ruling, and Guess 5's cost omits a visible effect
Where: c0249.md:264 (Guess 5), :265 (Guess 6).
Evidence: Guess 6 justifies two stacks with "Q1 rules out ('when no raft is claimable it drafts')". That is the 2026-11-11 wording the 2026-11-13 re-ruling replaced. The same precedence survives in the confirmed Idea (:132), which is what to cite. Guess 5's cost leaves out that once an item is readied, its rank stops counting in `list` and on the board (an active item is unset, so it sorts by number), and that `./zn stop` brings it back.
Critique: A guess the user vetoes from its text has to state its basis and its full cost.
Consequences: none.
Recommendation: Cite the Idea line in Guess 6, and add the view effect to Guess 5's cost.

### F12 [low] `rank.where` is a second reader of item paths, and it ignores the registry
Where: prototype `rank.luau:107-122`; used by `workread.facts` (over all of `ls-tree -r origin/main`), `cmd.list` and `cmd.rank`.
Evidence: It matches `^(.*)/issues/…` under any prefix. `publish.itemPath` splits by the registered roots and already strips `active/` and `done/`. So `next` reads items under a root that has left the registry as live items. None exist today: every match is under a registered `.tracker`.
Critique: zz-arch rule 5, one reader per format.
Consequences: none.
Recommendation: Derive the state from `publish.itemPath` (or `projects.rootOf`) plus the `retired/` folder, in one function every caller uses.
Lesson: zz-arch/one-reader-per-format

### F13 [low] A rank already on origin/main is reported to the app as "not saved" when the fast-forward fails
Where: prototype `main.luau` `cmd.rank` (`fail("ranked on origin/main, but pulling the main checkout failed …")`); `Service.qml:187-188`.
Evidence: A `./zn sync` or `ready` running at the same time in the main checkout holds `index.lock`. `git pull --ff-only` then fails after the push, and `rank` exits 1. The app's handler shows "priority not saved: <last stderr line>" and keeps the dragged order, though the rank is published.
Critique: The notice tells the person the opposite of what happened.
Consequences: The app's handler and its source pin in `app.test.mjs` change.
Recommendation: Once the publish succeeds, exit 0 with a warning on stderr, or with a distinct code the app reads as "saved, not pulled". Add a command.spec case with an `index.lock` in the fixture main checkout's `.git`.

### F14 [low] E5's record does not give the bounded command the mutation runner ran under
Where: c0249.md:334 (E5); `experiments/mutation-results.txt` header; `mutate.py.txt`.
Evidence: E3 records `./zn run --time 120 -- lune run …`. E5 records only results. The runner gives each spec a 900 s subprocess timeout, but nothing says how the runner itself was bounded.
Critique: Without the command, a reader can't rerun E5 as it ran or see that it was bounded.
Consequences: none.
Recommendation: Add the `./zn run --time <s> -- python3 -I experiments/mutate.py.txt` line E5 ran to its record.
Lesson: z-design/experiments-record-their-bounded-command

Lesson candidates (new, for the lead to write):
- z-design: a move that renumbers other items to make room writes values nobody chose. List every derived value that reads them (a raft's members' best rank, a band's best card), and pin that a move unrelated to it leaves it unchanged. Check: which orders read the values this command writes as a side effect, and does a spec pin that an unrelated move leaves each of them unchanged? (F2)
- z-design: measure a guess's cost at the input the shipped caller actually sends, not at hand-picked moves; the app's drop at the end of a column sends `last`. Check: for each caller that ships with the design (an app hook, a loop), which input does it send most, and did an experiment measure that one? (F5)

Verdict: changes
