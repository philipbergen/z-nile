# Review 001: c0276 (design mode)
Inputs: prep worktree `.worktree/prep-board-shows-lost-work` at 5d8fb89f with the staged c0276.md (sha256 5875a29b50fc…), check.sh (c1f69c4f95fa…), acceptance/board.spec.luau (e86e9f475c4d…), acceptance/verdicts.spec.luau (dae96a2a1552…); prototype origin/proto-c0276 2d999311 (its two specs equal the prep's; its check.sh differs only in labels); c0265's design (origin/prep-work-heartbeat); the c0274, c0275 and c0277 hand-offs; origin/R0084-board-live-server d46bd5f8 (c0121, PR #272); origin/omarchy-board-app (c0257, PR #243); z-nile/.tracker/issues/c0180/c0180.md; `./zn capture c0276` (8577a496, a confirmed capture: title, Problem and Non-goals unchanged, Solution only gained detail). The reviewer's runs were on a scratch clone of proto-c0276 with its origin removed (scratchpad `rv-c0276`, scripts `rv-c0276-mut.sh`, `rv-c0276-mut2.sh`, `rv-c0276-time.sh`). Nothing in the repository was edited.

### F1 [high] The served board and the board app are left to an open decision, an unpinned conditional and an obligation c0121 doesn't carry
Where: Design §4, c0121 row ("If c0121 has landed when this is executed, the executor wires … If c0276 lands first, c0121's executor does the same wiring … This is a decision I need confirmed: see the report."); §4, c0257 row ("Free order"); Implementation step 6; E6; `size: 190`.
Evidence:
- R0084 (c0121) is in code review: PR #272 is a draft and the branch tip d46bd5f8 is "R0084: review-001". The heartbeat raft can't land before all five layers are prepared, because c0265's PR #255 is held until then. So R0084 will most likely be on main when c0276 executes, and step 6 will then run. On R0084's branch, `serve.start` builds every model with `collect(o.root, facts)` (by default `board.collect(nil, root, facts)`) and renders it with `board.render(model(), markedJs)`. `serveBoard` passes no `collect` and never calls `buildBoard`. The served page therefore shows no marks unless step 6 is done.
- Step 6 has no acceptance criterion, no spec case and no Rules row (E6 says "reasoned, not run"). check.sh's AC1 to AC4 pass in three cases: `serveBoard` wired as designed, wired with the verdict read on the request path, or not wired at all.
- The other landing order hands the work to "c0121's executor". `git grep -n -E "c0276|heartbeat|withVerdicts|lost work" origin/R0084-board-live-server -- 'z-nile/.tracker/**/c0121*' 'z-nile/.tracker/rafts/**/R0084*'` finds one unrelated line (design-review-006:44, about `./zn beat`). R0084's prompt and c0121's sequestered specs, which can't be edited during execution, say nothing about this wiring.
- The c0257 app builds its model from `./zn board -O --out ~/.cache/znile-board/board.html` (`fetch.sh`) and sorts each column by its own priority (`sortByPriority` in Model.js). Its tiles never read `heartbeat`. The design's row says the app ignores the new keys ("Free order"). In effect the app shows neither the marks nor lost-first, and the design never says whether that is intended.
- The document says the c0121 question is undecided, yet it is marked `design: reviewed`.
Critique: The capture's first outcome is "The board shows each claim's verdict", and the README (on main and in the prototype) calls `./zn board --serve` "the same page live". Under the likely landing order, that outcome on the served page rests on a step that a wrong implementation passes. Under the other order, it rests on an obligation no other document holds (lesson z-design/quote-other-preps-before-promising). The author may be tempted to drop step 6 and say the served board is c0121's job. That is a scope cut the user has to decide. Keeping step 6 and adding more prose still leaves it unchecked.
Consequences: A spec for the served wiring needs `serve.luau` in the prototype. Today it isn't there (E6: the merge conflicts), so the spec forces a landing order (c0121 first) and a prototype rebuilt on R0084. A background verdict task in the server also brings new rules, and each needs a case:
- how often the task refreshes;
- a warning printed once per kind of failure, not once per TTL;
- nothing read while `guarded(true)`;
- what the first page shows;
- how a model cached by key picks up new verdicts. R0084's `model()` rebuilds only when `keyOf` changes or `serve.REBUILD` passes, so a wiring that only touches `collect` lags behind.

The cases would drive `serve.start` through its injected `listen`, `now` and `gh`, as c0121's own specs do.
Recommendation: escalate to the user: which boards does "the board" cover, and in what order do they land? Options:
- (a) Keep the full scope. Add `c0121` to `depends_on` and rebuild the prototype on R0084 (on main once it lands, or on its branch). Specify the served wiring exactly: where the verdicts are cached, how `model()` applies them, the TTL, one warning per kind of failure, and no read while guarded. Add an AC and spec cases for `serve.start` with injected `listen`, `now`, `gh` and a verdict source: the marks appear after the first background read, the request path makes no verdict read, and a guarded checkout reads nothing. Give each its Rules row and mutant. Cost: c0276 waits for R0084, and the raft grows by the wiring (about 40 lines) and its spec.
- (b) A `Scope decision (user, …)` line: the served page's marks become a new captured issue that depends on c0121 and c0276. Remove step 6 and its 40 lines from `size`.
- (c) For the c0257 app, either the app shows the marks (a change in PR #243 or a follow-up issue), or a recorded decision puts the app outside this outcome.

Once the user decides, delete "This is a decision I need confirmed" from the document and record the answer as a `Decided with the user` or `Scope decision` line.

### F2 [high] AC1 passes when rafts or the Ready bucket are never reordered and when a raft's marks are not drawn: four mutants survive
Where: Design §1, Order ("Inside each bucket of `views.rafts` and `views.issues` (ready, not, done)"); §2 ("in the heading of the issue and raft panes", "after the stage badge on a list row"); AC1 ("inside each bucket and band", "on cards, list rows and the pane"); verdicts.spec; board.spec.
Evidence: I applied each mutant alone on the scratch clone:
- Ma, rafts never reordered (`out.views = { rafts = m.views.rafts, issues = … }`): verdicts.spec 6 passed, 0 failed; board.spec 7 passed, 0 failed.
- Mb, only the Not-ready bucket ordered (`return { ready = g.ready, ["not"] = ordered(g["not"]), done = g.done }`): verdicts.spec 6 passed, 0 failed; board.spec 7 passed, 0 failed.
- Mc, raft pane heading drawn without `mark(r)`: verdicts.spec 6 passed, 0 failed.
- Md, list rows mark issues only (`(it.kind === "issue" ? mark(it) : "")`): verdicts.spec 6 passed, 0 failed.
- Control Me, `unknown` dropped from `MARKS`: verdicts.spec 5 passed, 1 failed.

The specs only ever put a lost card in one place: verdicts.spec's lost cards are issues in `views.issues["not"]` and in one band. Its raft verdicts are `nobeat` and `unknown`, never lost, and `out.rafts` is asserted to carry no mark. board.spec seeds issues only (c0010 to c0090, no raft). Yet a lost readied raft is the case the Ready bucket and the raft rows are there for: it is an `active-…` claim, the Rafts view lists it under Ready (zz-rules' board row: "a readied raft is Ready"), and c0265 judges "an unstarted readied raft" lost.
Critique: The Lessons pass says every bucket was seeded (`seed-every-enumerated-case`), but seeding a bucket without a lost item in it pins nothing. The tempting fix is one lost raft in `views.rafts["not"]`. That kills Ma but not Mb.
Consequences: none beyond the new cases.
Recommendation:
- In verdicts.spec's model, put a lost raft in `views.rafts.ready` after a raft that isn't lost, and a lost issue in `views.issues.ready` after another issue. Expect each lost item first.
- In the page case, give a raft a lost verdict and assert its mark in the Rafts list row and in the raft pane heading (click the raft, or jump to it with its id).
- Add Rules rows for "rafts are ordered", "every bucket is ordered", "the raft pane draws the mark" and "raft list rows draw the mark", with Ma to Md as their mutants.
Lesson: zz-test/seed-every-enumerated-case

### F3 [high] Offline, `./zn board` may fail outright and AC2 still passes: three failure modes the design lists have no case or row
Where: Design §3 (the four "What cannot be read" bullets; "The page is built in every case and the command exits 0"); Rules and mutants; board.spec's `SHIM` (lines 96-105); AC2 ("unreadable heartbeats build the page without marks, the build succeeding with one warning").
Evidence:
- The only failure board.spec's git shim can produce is a fetch whose arguments contain `hb-seen`. No case fails `fetch origin main`, makes the registry unreadable, or pushes a malformed `hb/` branch. Mutant Mf replaces the "origin/main could not be read" warning with `fail("board: origin/main could not be read")`, so `./zn board` exits 1 whenever origin can't be reached. On the scratch clone, board.spec still gives 7 passed, 0 failed. When origin is unreachable the heartbeats can't be read either: that is the captured "still builds when the heartbeats … cannot be read" in its most common form, and Mf breaks it while passing AC2.
- The Rules table has no row for the main-fetch, registry or malformed-branch paths.
- The case "unreadable heartbeats build the board without marks and say so once" only asserts that the stderr contains "heartbeats unreadable" (`has(r.stderr, "heartbeats unreadable")`). It never checks that the line appears once, although AC2 says "with one warning".
- By reading the code (not run): `cmd.board` calls `boardVerdicts()` outside any `pcall`. `claimsOf` reads each claim with `sh.git({"show", "origin/main:<p>"})`, which throws when the path is gone. Another worktree's fetch can move origin/main between `originTree()` and that read, for example after a `ready` moved the item to `active/`. Then `./zn board` exits 1 (`tracker board: …`), and `buildBoard`'s `pcall` turns the throw into "could not rebuild" and writes no page. Both contradict §3's "The page is built in every case".
Critique: An offline laptop is the board's most frequent failure. The design names its warning, but nothing keeps that failure from being fatal. The tempting fix is a case for the main fetch only, which leaves the throw path and the malformed-branch line unpinned.
Consequences: Wrapping the reads in a `pcall` adds one more message. The guard and the no-origin check must stay outside that `pcall`, so a protected checkout stays silent.
Recommendation:
- Make `boardVerdicts` total: after the guard, run its reads inside a `pcall`. On a throw, print one `warning: board: …; built without lost-work marks` line and return nil.
- Give board.spec's shim a `mainfail` switch for `fetch … origin main`, and add these cases:
  - origin/main unreadable: exit 0, the warning exactly once, no marks, and the page is written;
  - a malformed `hb/` branch, pushed from `other`: exit 0, its cure as one `warning: board:` line, and stale claims stay stale;
  - the existing unreadable-heartbeats case counts its warning (exactly 1).
- Add a Rules row for each, with Mf, "the warning printed once per claim" and "a malformed branch makes claims lost" as mutants.
Lesson: z-design/spec-design-correspondence

### F4 [medium] Every fixture publish now pays the verdict reads, the design's premise that the spec runner is protected holds only for the real checkout, and the whole suite was never run
Where: E4; Regression guard ("in the spec runner a protected checkout, so no verdicts"); AC3's label ("in the spec runner, a protected checkout, the board reads no remote"); Scalability; Affected specs; `Overrides: none`.
Evidence:
- `pickman_guarded` (z-nile/lib/fence.sh:238) answers `guarded` only when the git common dir is one of the real repositories the fence lists. A fixture under `.cache` with its own origin answers `unguarded`, which is why board.spec's marks appear at all. So `refreshBoard` runs `boardVerdicts()` on every publish, `land` and `sync` of every fixture spec, and so does every `./zn board` a fixture runs (c0070's `fresh()` included).
- c0070/board-refresh compares the rebuilt page with a fresh `./zn board` in the same unguarded fixture. Both builds read verdicts. It passes because every claim in the fixture is fresh, not because nothing is read.
- I timed three specs on the scratch clone (`rv-c0276-time.sh`: c0053/commands-claim, c0053/commands-prep and c0070/board-refresh), each with `boardVerdicts` as designed and with it stubbed by `if true or guarded(true) …`, in two alternating pairs:

  | pair | wall, designed vs stubbed | spec-seconds, designed vs stubbed | c0070/board-refresh, designed vs stubbed |
  |---|---|---|---|
  | 1 | 86.6 s vs 73.1 s | 192.3 vs 166.6 (+15%) | 77.1 s vs 59.5 s |
  | 2 | 63.0 s vs 45.4 s | 138.8 vs 99.4 (+40%) | 54.1 s vs 34.9 s |

  The machine's load varied between the pairs, but within each pair the designed engine was slower.
- The affected set is `ALL` (any path under `z-nile/engine/`), yet E4 ran a hand-picked 46 files.
  - Docs readers: `grep -rlF -e "zz-rules/SKILL.md" tests/acceptance tests/tooling` and `grep -rlF -e "README.md" tests/acceptance tests/tooling` (from `z-nile/`) list 9 readers that E4's list lacks: c0050/start-depends, c0081/skill-doc, c0107/keep, c0172/merge, c0191/docs, c0239/docs, tooling/dispatch-texts, tooling/affected and tooling/spend. I ran them, together with c0115/layout and board.spec (11 files): 83 passed, 0 failed.
  - Publishing specs: `grep -rln "\"status\", *\"c[0-9]*\", *\"preparing\"\|scripts/tracker.sh" z-nile/tests/acceptance z-nile/tests/tooling | wc -l` gives 63 spec files that run the tracker. Most of them are unrun.
- Each rebuild fetches `origin main` again, though its caller has just done so: `cmd.sync` fetches and pulls before `buildBoard`, `land` runs `git fetch --quiet origin main` right before `refreshBoard`, and a publish has just pushed main.
Critique: The user's standing rule is that slow gates are unacceptable. The design's cost section speaks only of the real board ("the cost the one ./zn status pays"), and its regression argument rests on a premise that is false for fixtures. The tempting fix is to exempt fixtures through a variable. That is a test-only switch in the engine, and it hides the real cost.
Consequences: Skipping the second fetch makes a rebuild rely on its caller's fetch. `cmd.board` still fetches, so F3's main-unreadable case then belongs to `./zn board` alone.
Recommendation:
- Run `z-nile/check.sh --affected` (it selects the whole z-nile suite) on proto-c0276 and on proto-c0265-raft, on one machine. Record both pass counts and spec-seconds in E4, and let that run replace the hand-picked list.
- Give `boardVerdicts` an argument saying that main is fresh. `buildBoard`'s callers pass it, so rebuilds skip the second fetch.
- Correct AC3's label, E4 and the Regression guard: fixtures are unguarded and do read the verdicts, and c0070 holds because both of its pages read the same verdicts.
- If the measured growth of the gate is still material, put the trade-off to the user with its number.
Lesson: z-design/prove-specs-pass-on-a-prototype; zz-review/lists-paste-their-search

### F5 [low] AC4 never checks that the board row names the marks: three of its six zz-rules words are already in c0265's Heartbeat paragraph
Where: check.sh AC4.
Evidence: Before c0276, `git show origin/proto-c0265-raft:z-nile/skills/zz-rules/SKILL.md | grep -cF -e <word>` already finds `parked`, `stale?` and `no beat` (1 line each). It finds none of `lost 35m`, `lost work comes first` or `unprotected checkout` (0 lines).
Critique: AC4's label says the board row names the marks, but a board row that names only `lost 35m` passes.
Consequences: none.
Recommendation: Grep the board row alone (the line that starts `| board |`) for `` `parked` ``, `` `stale?` `` and `` `no beat` ``, and keep the file-wide greps for the other words.

### F6 [low] The layer rule rests on two loose points: a worktree named like a numbered copy, and a misquoted autobeat exemption
Where: board.spec's setup (`worktree c0276-board-2`); E3 ("c0275's autobeat exempts only `beat`, `run` and `reap`").
Evidence:
- The c0277 hand-off makes `<name>-<n>`, with n numeric, a numbered copy of `<name>`. In it, `./zn worktree <name>` looks up "the `<name>` family … `.worktree/<name>` and `.worktree/<name>-<n>`". `c0276-board-2` is spelled like copy 2 of `c0276-board`, and c0277 isn't prepared yet, so its rule for a fresh name of that shape is still open.
- The c0275 hand-off exempts more than E3 says: "Every `./zn` command except `beat`, `run`, `reap` and `READ_ONLY` ones" autobeats.
Critique: The specs are sequestered and must still hold after c0277 lands. A worktree name that collides with c0277's pattern costs something and buys nothing. The misquote changes no case today, but it is the reasoning the next prep will reuse.
Consequences: none.
Recommendation: Name the second worktree so it can't be read as `<another worktree>-<n>` (for example `c0276-pub`), and quote c0275's exemption as the hand-off states it.

Verdict: changes
