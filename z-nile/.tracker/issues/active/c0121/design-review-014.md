# Review 014: c0121 (design mode)
Inputs: prep-board-server2 16e03f27 (c0121.md whole, check.sh, acceptance/ specs, harvest.md, design-review-011 to 013 and design-refute-011 to 013, `git diff d60b671e 16e03f27`); proto2-c0121 8ffccf92 (`git ls-remote origin refs/heads/proto2-c0121` → 8ffccf92…); origin/main 8714eafa after `git fetch origin main` (moved from 2f2fdb34 since round 3 by two spend commits only). Scratch clone `.worktree/prep-board-server2/.cache/r014/repo`, made by `/private/tmp/claude-501/-Users-philipbergen-code-pickman/1710de1d-709d-43fa-afde-dbe194852ce3/scratchpad/r014/setup.sh` (r013's script with PREP 16e03f27): `main` = origin/main plus the prep's c0121 folder; `raft` = main plus an empty start commit plus step 1's apply. Mutants: `/private/tmp/claude-501/-Users-philipbergen-code-pickman/1710de1d-709d-43fa-afde-dbe194852ce3/scratchpad/r014/mut.py`, applied one at a time on the clone's raft branch, with the engine restored after each (`engine clean`). Link probes: `.cache/r014/probe/m.js`, `m2.js` and `m3.js` (node with the vendored marked and the page's renderer). Every probe ran through `./zn run --time …`.
Round 4 of the second re-prep. Dropped from review-013: F1, F2, F3 (each fix holds, run below).

## What holds (run)
- **Step 1 on today's main (8714eafa).** `merge-base --is-ancestor 8ffccf92 origin/proto2-c0121` succeeds. Every non-new watched path exists, and `serve.luau` does not. `git log --first-parent 3993dca2..origin/main -- <watched>` prints nothing. The apply exits 0 with all 8 paths clean. `git diff 8ffccf92 HEAD -- <8 paths>` is 0 lines. `overrides.patch` is identical to the prototype's `docs.spec` diff, and that diff has not changed since fa44f524.
- **`./zn check c0121` on the replayed raft: 7/7.** c0120 `check-paths.spec`, run from the clone's `z-nile/`: 4 passed, 0 failed.
- **c0117's contract greps** on origin/main's `dispatcher.luau`, which is byte-equal to 3993dca2's: grep 1 gives `73` and `1848: st.follows = action.target`. Grep 2 gives exactly line 986. Grep 3 gives failed 8, lost 1, missing 1, stopped 1, tripwire 7, with the nil clears at 1790 and 2044.
- **Base on the clone**: page 9/0, server 26/0, guard 19/0.
- **Round 3's answers, and the mutants of every region the second re-prep changed** (killed means an assertion failed):

  | mutant | result |
  |---|---|
  | Z8 / N62 (a raft's state makes its member retryable) | guard 18/1, server 25/1 |
  | Z9 / N63 (a member's state makes its raft retryable) | guard 18/1; server 26/0, as the row says (server.spec's R0030 has a state) |
  | Y3 / N67 (the Stats encoded once for the server's life) | server 25/1 |
  | S3 (the `statsHtml` option ignored, the real one always used) | server 25/1 |
  | N55 (retry unguarded), Z6 (409 → 400), Z7 (retry follows like stop) | guard 18/1, 18/1, 16/3; server 25/1 each |
  | N59 (the generation read after `engineHash` yields) | server 25/1 |
  | N60 (version on every answer), N61 (generation without gh's version) | server 25/1, 23/3 |
  | X11 / N65, X12 / N66, Y4 (data kept on failure), Y5 (error kept on success) | server 25/1, 25/1, 24/2, 25/1 |
  | Y1 (the `live` block cached with the JSON, not spliced per poll) | server 25/1 |
  | Y2 (`built` never moves), Y11 (generation from gh's ask time), Y12 (from the build's clock) | server 25/1, 22/4, 25/1 |
  | X7 / N64 (title written raw), L3 (no stripping at all) | page 8/1 each |

  Survivors are in F1 to F5.
- **The splice and the generation**, read: no yield sits between `data = gh.data`, `gen` and the `checks` field. `engineHash()` is the constructor's last field. If two requests interleave, the worst case is that one of them encodes an extra time, and the next poll re-encodes under the right generation. Moving `live` elsewhere in the object would still be valid JSON, so it is an equivalent mutant, not a finding.
- **A state for an id the model lacks** (question 2): `serve.plan` refuses any action on an id outside `m.home` (400) before it reads a state. A `follows` naming a raft the model lacks falls back to the card's own id (`dispatchOf(m, follows) == nil`), as the design's stale-follow rule says. dispatch.luau:344 follows only `f.raft`, which is a raft in the tracker that the dispatcher syncs before it follows (dispatcher.luau:1725, 1886). No finding.
- **Scope**: the Problem, the title and the Solution are unchanged since 80125e67. The capture (`./zn capture c0121`, 4c2b7474) says "click a card for its worktree, its PR, its checks" (see F2).
- **Harvest**: round 3's note on zz-test/seed-every-enumerated-case is a general rule, not a restated finding.

### F1 [high] The link fixture leaves two plausible wrong renderers green: one that strips only tab and newline (so `< javascript:…>` keeps its href), and one whose href escapes only `&` (so a quote in the href opens `onmouseover`). Each runs script on the served page
Where:
- board.html:163 (`replace(/[\u0000- \u007f-\u009f]/g, "")`) and :167 (`esc(t.href)`).
- page.spec.luau:32-37 (LINKS: no leading space or control character in any destination, and no quote in any href). The attribute scan at :236-245 can only reject what the fixture contains.
- c0121.md:139 (§6: "the control characters and spaces a browser ignores **inside a scheme**") and the row at :330.

Evidence:
- **L2**, `/[\t\n\r]/g` in place of the class: page **9 passed, 0 failed**. In the probe (`m2.js mut`), `[s](< javascript:alert(1)>)` renders `<a href=" javascript:alert(1)">s</a>` and `[t](<\u000bjavascript:alert(1)>)` renders `href="\u000bjavascript:…"`. The base renderer gives `<p>s</p>` and `<p>t</p>`. A browser's URL parser removes leading and trailing C0 controls and spaces, so a click runs `javascript:` with the session token in reach. `[s](< javascript:alert(1)>)` is plain typeable markdown.
- **H2**, `String(t.href).replace(/&/g, "&amp;")` in place of `esc(t.href)`: page **9 passed, 0 failed**. The fixture's `a=1&amp;b=2` check is the only check on href escaping, and H2 passes it. Probe `m3.js` shows that marked keeps a raw `"` in a destination: `[r](https://a.example/"onmouseover="alert(1))` becomes `<a href="https://a.example/"onmouseover="alert(1)">`, which is an event handler on hover.

Failure scenario: an executor writes the stripping the design's own words describe ("inside a scheme" means tab and newline, which is what the URL standard removes inside), or escapes the href only for `&` (that is all the test asks about). The gate is green. A tracker document with `[docs](< javascript:fetch('/api/action',…)>)` or a quoted href then posts Stop or Retry from the served page, which is code review 001 F3 of R0084 again.

Critique: round 2 (review 012 F1) ruled that "every attribute the renderer writes is escaped". The fixture pinned the title's quote but not the href's. Round 1's stripping cases all put the ignored character inside the scheme (`java&#9;script`, `<java\tscript:…>`). This is the third round with a hole in this fixture. The tempting fix is to add these two links. The next hole would be the next character class.
Consequences: a leading-space destination needs angle brackets in markdown, so the fixture must use `<…>`. A raw U+0001 in a Luau string is `\1`. An href with a quote must stay visible as the link text when it is safe (https), with its quote escaped.
Recommendation:
- Test the renderer against the browser's rule, not against an example list. In page.spec, keep the `decoded()` check. Add a property case: for each prefix in {`" "`, `"\1"`, `"\31"`, `"\t"`, `"\n"`} and each dangerous scheme (javascript, data, vbscript), the destination `<prefix .. scheme .. ":x">` has no href whose decoded text has that scheme.
- Add `[q](https://a.example/"onmouseover="alert(1))`. The existing attribute scan then rejects `onmouseover`. Also require the href to read `https://a.example/&quot;onmouseover=&quot;alert(1)` exactly.
- §6: replace "inside a scheme" with "anywhere (tab, newline), and leading or trailing (any C0 control or space)", and say "the href and the title are escaped as attribute values (`&`, `<`, `>`, `"`)".
- Rows: L2 "only tab and newline stripped" and H2 "the href escapes only `&`", each killed.
Lesson: zz-test/seed-every-enumerated-case

### F2 [high] No issue card ever gets a PR or its checks: the server fills `pr` and `checks` on rafts only, so the capture's "click a card for … its PR, its checks" is unmet for every issue outside a launched raft, and G5's "its own PR" branch of `open` is dead code
Where:
- serve.luau:413-417 (`for _, r in m.rafts do … r.pr = …`; no loop over `m.issues`) and :171/:180 (`issuePr = i.pr`, which is always nil).
- board.luau:80 (`pr: Pr?, -- c0121's, as on Raft`).
- board.html:309-310 (the issue pane shows only `raft.worktree`, and `issue.pr || raft.pr`).
- c0121.md:30 (the Problem's seam line: "the Issue and Raft types carry `pr` and `checks` fields … for this issue to fill"), :122 (§4 open: "the item's own PR, else its raft's PR (from the `gh` cache)"), :128 (§5: "A raft gets the PR of its launched branch") and :378 (G5).

Evidence:
- `git grep -n -E '\.pr *=[^=]|pr = ' -- z-nile/engine` in the replayed clone: the only assignment of a card's PR is `serve.luau:415: r.pr = if hit then hit.pr else nil`. Nothing sets `Issue.pr`.
- guard.spec's `f0031` carries a hand-written `pr` (guard.spec.luau:76), so the guard case "opens an item's own PR" passes on a model the server never builds.
- Mutant O1 (`(raft and raft.pr) or issuePr`: the raft's PR before the item's own) gives guard 19/0 and server 26/0. No fixture has an item with both PRs.
- An issue under design has a branch and a PR of its own: `prep-<slug>` (zz-rules SKILL.md:58), opened by z-design, interactively or under `./zn dispatch <id>`.

Failure scenario: `./zn dispatch c0300` runs z-design in `.worktree/prep-<slug>` and opens its prep PR, with checks running. On the served board, c0300's card says "no PR" ("checks unavailable" while gh fails). Its pane shows no worktree. Open answers `400 c0300 has no PR and no worktree to open`. The design-review rounds, which are where an issue spends most of its time under the dispatcher, show none of the captured live state.
Critique: the Problem names `Issue.pr` as this issue's seam to fill, and G5 (a user decision) says "its own, else its raft's". The design wires only the raft half. The tempting fix is to delete the `issuePr` branch and reword G5. That is a scope cut on a captured outcome and a user decision, so it needs the user.
Consequences:
- An issue's prep PR stays in the gh cache after it merges (state `merged`). Under "own first", a member card in a running raft would then show its merged prep PR instead of the raft's live PR. So "own" needs a state rule.
- Not every prep branch is `prep-<slug>`. This issue's own second re-prep is `prep-board-server2`, slug `board-live-server`. Such an issue shows "no PR", which is acceptable if stated.
- The Issue model has no `slug` today, so board.luau must add it. board.luau is in Touched modules.
Recommendation:
- Fill `Issue.pr` and `Issue.checks` from the gh cache by `prep-<slug>` in `model()`, beside the raft loop. Let an issue's own PR win in `prText` and `open` only while it is open or draft; otherwise the raft's PR wins.
- Show the prep worktree in the issue pane when `facts.worktrees` has `prep-<slug>`, and fall back to it in `open` after the PRs.
- Spec cases:
  - server.spec: an issue with `slug: s1` and a gh PR on `prep-s1` shows that PR and its checks, and Open opens it.
  - guard.spec: an item with an open own PR and a raft PR opens its own (kills O1). An item with a merged own PR and an open raft PR opens the raft's.
- Rows: O1, "issue PRs never filled", and "a merged own PR shadows the raft's".
- If the author prefers raft-only, escalate to the user: (a) the above, which costs about 40 lines and 3 cases; (b) a `Scope decision` that an issue card shows only its raft's PR and worktree, which drops the dead branch and leaves cards under design blank.

### F3 [medium] G9 keeps the Retry button because "the answer is shown under the buttons", but page.spec shows only a Stop answer of 200: a page that turns a 409 into "the server did not answer", or drops the answer's text, passes
Where:
- board.html:323-325 (`act`).
- page.spec.luau:80-84 (the fetch stub answers every `/api/action` with 200), :99 (only a Stop click) and :260 (`has(shown.paneAfter, "stop: 200")`).
- c0121.md:383 (G9: "the page keeps its Retry button (the answer is shown under the buttons)") and :344 (AC3: "posts Stop … and shows the answer").

Evidence:
- **P1** (`if (!r.ok) throw new Error(String(r.status))` before `r.text()`, the pattern `poll()` uses at board.html:558): page **9 passed, 0 failed**. With P1, a Retry on a card that never ran shows "retry: the server did not answer". The user is not told it was refused, or why.
- **P2** (`return action + ": " + r.status;`, so the body is dropped): page **9 passed, 0 failed**. The pane then shows "retry: 409" with no "nothing to retry for c0300: it has never run".

Failure scenario: an executor copies `poll()`'s `if (!r.ok) throw`, which is a natural refactor. A Retry click on a backlog card is then refused correctly on the server, but the page says the server is down. That is the opposite of what G9's "the answer is shown" promised when the user decided to keep the button.
Critique: the server half of G9 is pinned in three shapes (rounds 1 and 3). The page half, which is the only part the user sees, is not pinned at all. The tempting fix is to change the stub's status to 409 for every action, which drops the 200 path.
Consequences: the stub must answer per request, so the harness needs a way to choose. The same holds for Stop's 409 and for a 500 from the runner.
Recommendation:
- In the harness, after the Stop click, click Retry on the same card with the stub answering `409` and body `refused: nothing to retry for f0021: it has never run`.
- Assert that the pane shows `retry: 409 refused: nothing to retry for f0021` and still shows Stop, Retry and Open.
- Also assert that the Stop answer carries its body (`stop: 200 {"ok":true,"output":"stopped"}`).
- AC3: "shows each action's status and answer, a refusal included".
- Rows: P1 and P2, killed.

### F4 [medium] The served Stats are never compared with the real Stats: round 3 replaced `board.statsHtml` with a stub in server.spec, so a `board.statsHtml` that returns `""`, or a wrong default, passes, and the served page blanks its Stats on the first poll (repeat of review-013 F2's consequence)
Where:
- server.spec.luau:136-138 (the stub `<p>stats of build N</p>` in the shared `start()`); the two other servers (:598-647 and :649-697) use the default but assert only `stale` and 200.
- serve.luau:355 (`local statsOf = o.statsHtml or board.statsHtml`).
- board.luau:484-486 (`board.statsHtml`, new in c0121).
- design-refute-013 F2 ("consequences: none").

Evidence:
- **S1** (the default `statsOf` returns `""`): server 26/0, page 9/0.
- **S2** (`board.statsHtml` returns `""`): server 26/0, page 9/0.
- `git grep -n statsHtml -- z-nile/tests` finds no spec that calls `board.statsHtml` or reads a served `statsHtml`'s content. c0118's page.spec pins only that `znBoard.load` replaces the section with whatever text it gets (`"<p>fresh stats</p>"`, c0118/page.spec.luau:103).

Failure scenario: `board.statsHtml` returns the wrong part, or nothing. The served page renders Stats once from `board.render`, and the first poll five seconds later replaces them with `""` or with a nested section. Every spec is green.
Critique: review 013 F2 recommended wrapping the real function, "so it stays exercised". Its Consequences said that injecting a stub would take the real `board.statsHtml` out of server.spec. The refute took the stub and answered "consequences: none". This round therefore questions the mechanism: a cache test whose stub replaces the function it caches cannot see that function's errors.
Consequences: wrapping makes the Stats text depend on the fixture's spend rows. Assert on an anchor the fixture controls, not on today's layout.
Recommendation:
- In `start()`, `statsHtml = function(m) return require("@znile/engine/board").statsHtml(m) .. "<!-- build " .. builds .. " -->" end`. The encode-once case keeps telling builds apart.
- In the "default engine hash" server, which uses the default `statsOf`, assert that `/api/state`'s `statsHtml` equals the text between `<section id="stats" hidden>` and `</section>` in `board.render` of the same model (the page's first Stats).
- Rows: S1 and S2, killed.
Lesson: zz-review/run-the-evidence-you-cite

### F5 [low] Stop on a member with no state of its own, in a raft that runs, answers "409 nothing is running for f0025" while its raft runs, and nothing pins that answer, so a mutant that sends it to the raft's run passes
Where: serve.luau:139-141; guard.spec.luau:52 (`f0025`, used only for retry) and :216-224 (the stop-409 case, `c0099` only); c0121.md:120 (§4 stop: "With no state for the card's id … 409").
Evidence: **ST1** (a stateless member whose raft has state plans `dispatch stop <raft>`) gives guard 19/0 and server 26/0. Review 013 F1's Consequences asked for this answer to be pinned "so a later edit is deliberate". The refute added only the retry assertions.
Critique: either answer may be right, but which one is chosen should be a decision. Today the card says "nothing is running" beside a raft that is running, which misleads.
Consequences: if Stop should reach the raft's run, that is a design change: stop then follows `issue.raft` as well as `follows`.
Recommendation: in the stop-409 case, assert `serve.plan(MODEL, "stop", "f0025")` gives 409. Word the refusal so it is true: "nothing is running for f0025 (its raft R0020 has a run: stop it on R0020's card)". Add row ST1.

### F6 [low] Stale or inconsistent text
Where and Evidence:
- c0121.md:153: one sentence gives two figures for the same quantity: "a changed `gh` answer about 0.10 s, so about 0.40 s …" and then "(…, and a changed `gh` answer measured 0.13 s)".
- c0121.md:230: the Test plan names a case "retry on a card that never ran: a loose issue, a member of a raft that runs, a raft with no state whose member has one" in `guard.spec.luau and server.spec.luau`. No case has that name. These are assertions inside the two existing retry-409 cases, and server.spec has no stateless-raft assertion.
- c0121.md:139 (§6) "inside a scheme": see F1.
Recommendation: give one figure (0.13 s, measured). Fold line 230 into the two existing Test plan lines (:210, :228), naming what each asserts.
Lesson: z-design/restated-rules-move-together

Candidate lesson (for the lead): zz-review: when a refute answers "consequences: none" to a review whose Consequences named one, the next round runs the mutant those consequences predicted. Check: for each Consequences line of the previous round, is there a case or a refute sentence that answers it?

Verdict: changes
