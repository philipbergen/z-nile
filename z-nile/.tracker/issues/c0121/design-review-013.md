# Review 013: c0121 (design mode)
Inputs: prep-board-server2 d60b671e (`git ls-remote` agrees; c0121.md whole, check.sh, acceptance/ specs, overrides.patch, harvest.md, design-review-011/012 and design-refute-011/012, `git diff 30df1796 d60b671e`); proto2-c0121 8ffccf92 (`git ls-remote origin refs/heads/proto2-c0121` → 8ffccf92…); origin/main 2f2fdb34 after `git fetch origin main` (main moved from f30d1d85 since round 2: R0089, c0279's prep, two spend commits; none touches a watched path). The R0084 code review read from `R0084-board-live-server` d46bd5f8. Scratch clone `.worktree/prep-board-server2/.cache/r013/repo`, made by `/private/tmp/claude-501/-Users-philipbergen-code-pickman/1710de1d-709d-43fa-afde-dbe194852ce3/scratchpad/r013/setup.sh` (r012's script with PREP d60b671e): `main` = origin/main plus the prep's c0121 folder, `raft` = main plus an empty start commit plus step 1's apply. Mutants: `/private/tmp/claude-501/-Users-philipbergen-code-pickman/1710de1d-709d-43fa-afde-dbe194852ce3/scratchpad/r013/mut.py`, one at a time on the clone's raft branch, engine restored after each (`engine clean`). CPU probe: the clone's `z-nile/.cache/probe/cpu3.luau` (r012's `cpu2` plus a mode where each poll gets a changed `gh` answer, the periodic rebuild off). Every probe ran through `./zn run --time …`.
Round 3 of the second re-prep. Dropped from review-012: F1, F2, F3, F4 (each fix holds, run below; the parts of F3 and F1's recommendation that were not taken up are in F3 below).

## What holds (run)
- **Step 1 on today's main (2f2fdb34)**: `merge-base --is-ancestor 8ffccf92 origin/proto2-c0121` succeeds. Every non-new watched path exists, and `serve.luau` does not. `git log --first-parent 3993dca2..origin/main -- <watched>` prints nothing. The apply exits 0 with all 8 paths clean. `git diff 8ffccf92 HEAD -- <8 paths>` is 0 lines.
- **`./zn check c0121` on the replayed raft: 7/7.** c0120 `check-paths.spec` from the clone's `z-nile/`: 4 passed, 0 failed.
- **AC7's patch is unchanged.** `overrides.patch` is byte-identical to d60b671e's and to 30df1796's (`cmp`), and to the prototype's `docs.spec` diff. Its last change is b061bc22.
- **c0117's contract greps** on origin/main's `dispatcher.luau` (byte-equal to 3993dca2's): grep 1 gives `73: follows: string?` and `1848: st.follows = action.target`. Grep 2 gives exactly line 986. Grep 3 gives failed 8, lost 1, missing 1, stopped 1, tripwire 7, with the nil clears at 1790 and 2044. The follow branch (:1847-1862) switches to the raft's own state folder, so a raft that runs has its own state, which stop's and retry's rules rely on.
- **Base on the clone**: page 9/0, server 26/0, guard 19/0, the author's counts.
- **Round 2's mutants and mine** (killed means an assertion failed):

  | mutant | result |
  |---|---|
  | X7 / N64 (title written raw) | page 8/1 (the link case) |
  | X11 / N65 (a failure never moves gh's version) | server 25/1 (the new failure/recovery case) |
  | X12 / N66 (the sig remembers only successful output) | server 25/1 (the same case) |
  | Y1 (the `live` block cached with the JSON, not spliced per poll) | server 25/1 (the stale-engine case) |
  | Y2 (`built` never moves) | server 25/1 (encode-once) |
  | Y4 (gh's data kept on a failure) | server 24/2 |
  | Y5 (gh's error kept after a success) | server 25/1 |
  | Y11 (generation from gh's ask time, not its version) | server 22/4 |
  | Y12 (generation from the build's clock, not the build count) | server 25/1 |
  | Z6 (a never-ran retry answered 400) | guard 18/1, server 25/1 |
  | Z7 (retry follows like stop) | guard 16/3, server 25/1 |
  | Y7 (`sig = out`: nil on every failure) | server 26/0. This is an equivalent variant: the model it serves is the same in every sequence. No finding. |
  | **Y3 (the Stats encoded once, never again)** | **server 26/0**, see F2 |
  | **Z8 (retry allowed on a member with no state when its raft has one)** | **guard 19/0, server 26/0**, see F1 |
  | **Z9 (retry allowed on a raft with no state when a member ran)** | **guard 19/0, server 26/0**, see F1 |

- **The new server case tests what it says.** Each half starts from a key change at a fresh clock. The failure half asks `gh` 31 s after the settle, and the recovery half asks it 31 s after its own settle, so neither window reaches the 60 s rebuild. `builds` is asserted unchanged in both. The new page assertions reject any `on…` attribute and anything outside a quoted attribute in each `<a …>` tag, and they require `title="x&quot;`. An escape that left `"` alone would fail on the fixture.
- **The splice and the generation under concurrency**, read and run: no yield sits between the data read, `gen` and the `checks` field (the `live` constructor evaluates `checks` before `engineHash()` yields). `m.live = nil`, the encode and the restore don't yield either. `model()` in a non-final argument (`board.render(model(), …)`, `serve.plan(model(), …)`) drops the generation.
- **CPU per changed `gh` answer**: (2.98 − 0.40) s / 20 = 0.13 s (the lune process's own `ps -o time`, load 13 on 18 cores), against the design's "about 0.10 s". The real `gh` answer (`gh-real.json`, 200 PRs) changed in 19 ten-minute windows since 2026-11-08 00:00Z (check-run `startedAt`/`completedAt`), a few an hour, so it adds little.
- **G9/G10/F3 of R0084's code review**: F1's rule (409 for a card with no run state) is in `serve.plan` (serve.luau:151-157) and pinned for a loose issue. F2's fix (encode per generation) holds, with the Stats gap below. F3 (the link schemes) holds after rounds 011 and 012. Nothing else in that review is open.
- **Scope**: the Problem, the title and the Solution are unchanged since 80125e67. The G9 and G10 lines are recorded.
- **Harvest**: the two notes added this round (zz-arch links: every attribute escaped, foreign attributes rejected; zz-test seed-every-enumerated-case: a counter that a periodic rebuild also moves) apply to other rafts. They are not restated findings.

### F1 [medium] The retry 409 is pinned on one shape of never-ran card, a loose issue. A retry rule that asks the card's raft (Z8) or its members (Z9) passes all four specs and starts a whole chain
Where: serve.luau:151-157 (`if dispatchOf(m, id) == nil then return nil, …, 409`). guard.spec.luau:30-110 (MODEL: every member of R0020 has its own state; R0030 has none, but no case retries it) and :223-234 (the only never-ran retry is `c0099`, which has no raft). server.spec.luau:101-125 (facts: only `c0099` has no state, with `raft:` empty, :211) and :301-311. c0121.md:121 (§4 retry), :327 (row), :339 (AC1).
Evidence:
- Z8 replaces the guard with "refuse only when neither the card nor its raft has state". guard 19/0, server 26/0.
- Z9 replaces it with "a raft with no state may be retried when one of its members has state". guard 19/0, server 26/0.
- Both are realistic shapes of the rule. A board card for a member reads naturally as "part of the raft's run". The stop rule next to it already walks from a member to its raft. A dispatched raft's members routinely have no state of their own: the raft was launched with `./zn dispatch R…`, and its members were prepared interactively.

Failure scenario under Z8: R0090 runs under the dispatcher, and its member c0300 was prepared by hand, so it has no state. The person clicks Retry on c0300. The server runs `./zn dispatch retry c0300`, which, as R0084's F1 traced, makes the folder, loads `blank` (mode `chain`) and runs `dispatcher.chain` from c0300's tracker state. The user ruled that start out in G9.

Under Z9: a raft whose issue chain stopped before it followed (the member has state, the raft none) gets `./zn dispatch retry R…`, a fresh execution chain.

Critique: G9 says "a card the dispatcher has no run state for", which means the card's own state. The fixture holds only one of the three kinds of card the rule walks (a loose issue, a raft member, a raft). The tempting fix is to add one more id to the existing case. Add both kinds, or the other mutant survives.
Consequences: a member with no state of its own, in a raft with state, also meets stop's 409 (§4: "With no state for the card's id"). The new fixture member therefore pins stop's answer too: today 409 (the card's own state decides), which the design states. If the user wanted Stop on such a member to reach the raft's run, that would be a design change, not this fix. Name it in the case so a later edit is deliberate.
Recommendation:
- guard.spec MODEL: add a member of R0020 with no `dispatch` (e.g. `f0025`, `raft = "R0020"`). In the retry-409 case, assert `serve.plan(MODEL, "retry", "f0025")` gives nil, 409 and "nothing to retry for f0025: it has never run", and the same for `serve.plan(MODEL, "retry", "R0030")` (a raft with no state whose member `f0031` has state). In the stop-409 case, assert `stop` on `f0025` gives 409.
- server.spec: give the fixture tracker a member of R0020 with no state in `facts.dispatch`, and assert its retry answers 409 with `runs` unchanged.
- Rows: Z8 "retry consults the card's raft" and Z9 "retry consults the raft's members", each killed in guard and server. Extend row :327's case names.
Lesson: zz-test/seed-every-enumerated-case

### F2 [medium] The Stats half of the per-generation cache is unpinned: Stats encoded once at start and never again pass server.spec 26/0, so a served page's Stats freeze for the server's life
Where: serve.luau:479-485 (`encoded.stats = board.encode(statsOf(m))` inside `if encoded.gen ~= gen`) and :492. server.spec.luau:371-408 (the encode-once case asserts only `type(s.statsHtml) == "string"`, :396) and :339. c0121.md:132 (§5: "the model's JSON, with `live` left out, and the Stats are kept per generation"). The Rules table (:327-333) has no Stats row.
Evidence: mutant Y3 (`if encoded.stats == "" then encoded.stats = board.encode(statsOf(m)) end`) gives server **26 passed, 0 failed**. No spec compares one poll's `statsHtml` with another's. The server reads the real `board.statsHtml` (no `statsHtml` option in `start()`, server.spec.luau:62-141), and the fixture's Stats text is the same before and after every rebuild the specs cause.

Failure scenario: a raft's build rows reach its worktree's `spend.md`, the key changes and the model is rebuilt. The polled model shows the new spend on the card, while the Stats section (cost per issue, rework) keeps the numbers from the moment the server started, for up to three days (§Scalability). Nothing on the page says so.
Critique: §5's rule has two halves, and the table pins only the model's. The tempting fix is a substring check that `statsHtml` is non-empty, which Y3 also passes.
Consequences: injecting a `statsHtml` stub would take the real `board.statsHtml` out of server.spec. Wrap the real one instead, so it stays exercised. If the Stats came to depend on `gh`, the per-gh-answer re-encode would matter. Today they do not, and an extra encode is harmless.
Recommendation:
- In `start()`, pass `statsHtml = function(m) statsCalls += 1; return board.statsHtml(m) .. "<!-- build " .. builds .. " -->" end`.
- In the encode-once case, assert that the three steady polls carry the same `statsHtml` and that `statsCalls` did not move across them. Then assert that the poll after `key = "k-encode"` carries a different `statsHtml` (the new build's marker).
- Row: "the Stats are kept per generation and follow a rebuild", with mutant Y3 "the Stats encoded once", killed.

### F3 [low] Text that did not follow round 2's fixes
Where and Evidence:
- **§6 and AC3 still name only the href.** Round 2 made the title (and "nothing but the attributes it writes") part of the rule: row :333, the page.spec assertions, the harvested note. §6 (c0121.md:139) still says only "the href is escaped (so the attribute holds exactly the string that was tested)". AC3 (:341) says "a document link keeps only a safe scheme". Review 012 F1 recommended extending §6 and the row to "every attribute the renderer writes is escaped". Only the row was extended.
- **Mutant ids.** :189 and :261 say the rebuilt prototype's rows are "N52 to N66". The table has N52 to N61 and N64 to N66, with no N62 and no N63 (`grep -n 'N6[23]'` over the folder: no hit).
- **The lifetime is stated without its condition.** :153 says the limit "is reached after about three days". That figure is 0.37 s + 12 × 2.7 ms a minute: one tab, no key change but the 60 s age, no changed `gh` answer. Each commit in any worktree, fetch of origin/main or dispatcher state write forces an extra 0.37 s rebuild. A changed `gh` answer is 0.13 s measured (above), not "about 0.10 s". Review 012 F3 recommended "less while rafts commit or the dispatcher runs", and the refute did not say why that part was left out.

Critique: an executor checks §6 against the code, and a user plans restarts by the lifetime. Neither is wrong enough to fail a check.
Consequences: none.
Recommendation:
- §6: "the href and the title are escaped, and the anchor carries no attribute but these". AC3: add "with every attribute it writes escaped".
- Renumber, or say "N52 to N61, N64 to N66".
- :153: "about three days with one idle tab; less while worktrees commit, main is fetched or the dispatcher writes state (each forces a 0.37 s rebuild)", and "a changed gh answer about 0.13 s".
Lesson: z-design/restated-rules-move-together

Verdict: changes
