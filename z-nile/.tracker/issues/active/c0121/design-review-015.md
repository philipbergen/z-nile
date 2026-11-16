# Review 015: c0121 (design mode)
Inputs: prep-board-server2 87afeb9e (c0121.md whole, check.sh, acceptance/ specs, harvest.md, design-review-014 and design-refute-014, `git diff 87afeb9e~1 87afeb9e`). proto2-c0121 is at a1cdbcf8: `git ls-remote origin refs/heads/proto2-c0121` gives a1cdbcf8…, and `git diff 8ffccf92 a1cdbcf8` is the G11 change to `serve.luau` only. origin/main is 0b0a4017 after `git fetch origin main`.
Scratch clone: `.worktree/prep-board-server2/.cache/r015/repo`, made by `/private/tmp/claude-501/-Users-philipbergen-code-pickman/1710de1d-709d-43fa-afde-dbe194852ce3/scratchpad/r015/setup.sh`. That is round 4's script with PREP 87afeb9e and tip a1cdbcf8. In it, `main` is origin/main plus the prep's c0121 folder, and `raft` is main plus an empty start commit plus step 1's apply.
Mutation runner: `/private/tmp/claude-501/-Users-philipbergen-code-pickman/1710de1d-709d-43fa-afde-dbe194852ce3/scratchpad/r015/mut.py`. It applies one mutant at a time on the clone's raft branch and restores the engine after each (`engine clean`).
Probes:
- `.cache/r015/repo/r015-probe.luau`: the real `serve.start` with stub effects, run on the clone's real tracker against today's real `gh pr list` output (`.cache/r015/gh.json`, 198 entries).
- `.cache/r015/probe/attack.js`: node, the vendored marked plus the `marked.use` block and `esc` cut verbatim from board.html. Each `href`/`src` is entity-decoded, then resolved with WHATWG `new URL`.

Every probe ran through `./zn run --time …`.
Round 5 of the second re-prep (the final round). Dropped from review-014: F1, F3, F4, F5, F6 (each fix holds; the evidence is below). Round 4's F2 is answered by G11. Its mechanism is judged afresh in F1 to F3.

## What holds (run)
- **Step 1 on today's main (0b0a4017).**
  - `merge-base --is-ancestor a1cdbcf8 origin/proto2-c0121` succeeds.
  - Every non-new watched path exists, and `serve.luau` does not.
  - `git log --first-parent 3993dca2..origin/main -- <watched>` prints nothing.
  - The apply exits 0 with all 8 paths clean, and `git diff a1cdbcf8 HEAD -- <8 paths>` is 0 lines.
  - `overrides.patch` is identical to the prototype's `docs.spec` diff.
- **`./zn check c0121` on the replayed raft: 7/7.** c0120 `check-paths.spec`, run from the clone's `z-nile/`: 4 passed, 0 failed.
- **c0117's contract greps** on origin/main's `dispatcher.luau` (`cmp` equal to 3993dca2's):
  - grep 1: lines 73 and 1848.
  - grep 2: line 986 only.
  - grep 3: failed 8, lost 1, missing 1, stopped 1, tripwire 7, with the nil clears at 1790 and 2044.
- **Base on the clone**: page 10/0, server 27/0, guard 19/0.
- **Mutants of the earlier regions**, re-run on the replay (each killed on an assertion):

  | mutant | result |
  |---|---|
  | L2 / N68 | page 9/1 |
  | H2 / N69 | page 9/1 |
  | X7 / N64 | page 9/1 |
  | P1 / N70 | page 9/1 |
  | P2 / N71 | page 9/1 |
  | S2 / N72 | server 25/2 |
  | ST1 / N73 | guard 18/1, server 26/1 |
  | N55 | guard 18/1, server 26/1 |
  | Z8 / N62 | guard 18/1, server 26/1 |
  | N59 | server 24/3 |
  | N60 | server 26/1 |
  | X11 / N65 | server 26/1 |
  | Y1 (live block cached) | server 26/1 |
  | Y3 / N67 | server 26/1 |

- **G11's mutants as listed**, each killed:

  | mutant | result |
  |---|---|
  | N74 (merged counts) | server 25/2 |
  | N75 (substring) | server 25/2 |
  | N76 / O1 (raft's PR first in `open`) | server 26/1 |
  | I12 (page: raft's PR first) | page 9/1 |
  | I17 (`title` dropped in `parsePrs`) | guard 18/1, server 25/2 |
  | I2 (laid only on a rebuild) | server 25/2 |

- **The link renderer**, against 61 attacks in node (`attack.js`):
  - Kept anchors: no `href` resolves to a scheme other than http, https or mailto, and no anchor carries an `on*` attribute.
  - Every entity-encoded scheme is written escaped (`jav&amp;#x61;script:`), so the browser sees the literal text and resolves it as a relative URL.
  - Leading space or C0 control, `&#9;`, `&Tab;`, `javascript\t:`, U+00A0 and U+3000 are rejected or inert.
  - Quotes in an href or a title are escaped, `<javascript:…>` autolinks render as text, and raw `<a>` is escaped.
  - The only hit is `[![i](javascript:x)](https://ok)`, which gives `<img src="javascript:x">`. §6 deliberately leaves images to marked, and an `img src` runs no script. Marked percent-encodes a quote in an image src (`x%22onerror=…`), so the src cannot break out of its attribute. No finding.
- **The splice and cost**:
  - The new `title` and `Issue.pr` fields leave the model's JSON an object, so the splice stays valid (server 27/0).
  - One lay of issue PRs on the real tree is 272 issues × 198 PR entries: **0.004 s of CPU** (`r015-probe.luau`). At 400 × 200 that is under 10 ms per generation. No finding.
- **The `laidFor` guard's own logic**:
  - `gen` is `{built}.{gh.version}`, two integers joined by a dot, so no two generations collide.
  - When gh fails or has not answered, `data` is nil, so the lay clears every issue's PR.
  - The lay happens before `engineHash` yields, as `gen` does.
  - The weakness is that no case drives it across generations (F3).

### F1 [high] G11's rule ("a PR whose title names the issue id as a word") puts another item's PR on 4 of the 13 issue cards it fills from today's real PRs, and Open opens that PR
Where:
- serve.luau:421-441 (`needle = [^%w]{i.id}[^%w]` against every open or draft title)
- c0121.md:129 (§5: "the newest open or draft PR whose title names the issue id as a word")
- c0121.md:395 (G11's wording)
- server.spec.luau:46-55 (GH_JSON: each title names exactly one id)

Evidence: `r015-probe.luau` ran the real `serve.start` on the clone's tracker, with today's `gh pr list` output as the gh stub. It filled 13 issue cards. These four are wrong:
- `c0248` (backlog, `design: draft`, no PR of its own) gets **#260** "WIP: c0262 Full force final review (held until c0248 and c0260 are prepared)". `open c0248` answers `200 {"opened":".../pull/260"}`.
- `c0260` also gets **#260**, which is c0262's prep PR.
- `c0141` gets **#167** "tracker: raft R0062 regrouped (c0141's record refreshed)", a rafting PR.
- `c0131`, which is done in R0047, gets **#172** "R0061: c0131 header, …", another raft's draft PR.

Each card then shows that PR's checks as its own. The fixture cannot see this: every title in GH_JSON names exactly one id. The real producer writes titles that name several ids: 16 of today's 200 PRs do (`re.findall` over the titles).

Failure scenario: the executor implements §5 as written, and AC2 passes. On the served board, the card for an untouched backlog issue says "#260 draft, checks …", and Open opens c0262's PR. This is the misattribution G11 was meant to remove ("a card for work under design shows its prep PR"). It also happens whenever a prep or WIP PR mentions an issue it waits on, which is common.

Critique: "names the issue" was the user's shorthand for "is this issue's PR". The word-match reads it as "mentions". The tempting fix is to exclude ids inside parentheses. That breaks on the next phrasing ("blocked by c0248:", "R0061: c0131 …").

Consequences: both conventions in the repository put the PR's own item first. z-design's prep commit is `tracker: prep c0010 <title>` (z-design SKILL.md:77). A raft's PR is `{raft.id}: {title}` (main.luau:3304). The first tracker id in a title, of any type (`[A-Za-z]%d%d%d%d` as a whole word), is therefore the item the PR is for. Run on today's open PRs, that rule gives 9 right and 0 wrong:
- #260 goes to c0262 only.
- #167 goes to R0062, a raft, so no issue card takes it.
- #172 goes to R0061, so c0131 takes nothing.

Under this rule a member of a launched raft never takes its raft's PR as "its own", and that is correct: `raft.pr` already fills it. A title that starts with no id ("WIP: Fix …") gives no issue PR.

Recommendation:
- §5 and `model()`: an issue's own PR is the newest open or draft PR whose title's first tracker id (a whole word, upper or lower case as written) is the issue's id.
- Record this as the reading of G11's "names the issue", with the two conventions cited. If the author reads it as a change to G11, ask the user, offering this rule and the current word-match.
- Spec cases (server.spec GH_JSON):
  - `"WIP: f0021 … (held until c0099 is prepared)"`: on f0021, not on c0099.
  - `"tracker: raft R0020 regrouped (f0022's record)"`: on no issue.
  - `"R0020: f0021 …"`, an open raft PR naming a member: on no issue card as its own. The raft's PR still shows through `raft.pr`.
- Rows: "any id in the title" (today's rule) and "the last id in the title", each killed.

Lesson: zz-test/seed-every-enumerated-case (the real producer's titles name several ids; the fixture never does)

### F2 [high] G11 says it makes "click a card for its worktree, its PR, its checks" hold for work under design, but §5 leaves the worktree out of an issue card "because a prep worktree is not in the model". It is in the model's facts
Where:
- c0121.md:395 (G11: "so the captured 'click a card for its worktree, its PR, its checks' holds for work under design too")
- c0121.md:129 (§5: "The issue's worktree is not shown (a prep worktree is not in the model)")
- board.html:309 (the issue pane's worktree row is `raft && raft.worktree` only)
- board.luau:846-848 (`worktreeOf[w.branch] = w.path` from `facts.worktrees`, already built for every model)
- dispatcher.luau:68 (c0117's state also carries `worktree`)
- the capture (Problem line 20)

Evidence:
- `git worktree list` in the main checkout has `/…/.worktree/prep-ticket-provenance [prep-ticket-provenance]`. That is the head branch of #266, c0263's open prep PR, which the G11 lay finds.
- The same model build reads `git worktree list --porcelain` into `facts.worktrees` (board.luau:677-685) and maps branch to path (846-848). The PR entry is keyed by that branch (`parsePrs` returns `byBranch`).
- So the issue's worktree is one lookup away (`worktreeOf[branch of its own PR]`). Yet c0263's served card shows its PR #266 beside an empty worktree row.
- No `Scope decision` or `Decided with the user` line covers leaving it out. G11's question offered only PRs, and its recorded wording claims the worktree half holds.

Failure scenario: the user runs `./zn dispatch c0300`. The served card shows the prep PR and its checks but no worktree, and Open opens the PR. G11's record says the captured clause holds for work under design, but the card does not show it. The user decided G11 on that claim.

Critique: round 4 (F2's Recommendation) asked for the prep worktree. The refute declined with "not in the model", which board.luau contradicts. The tempting fix is to reword G11. That narrows a captured outcome under a user decision, so it needs the user.

Consequences: the lay already iterates `data` by branch, so it can record `branch` with the best entry. board.luau must then expose `worktreeOf` (or `facts.worktrees`) to `serve.luau`, or carry the branch on `Pr`. A raft member's pane keeps `raft.worktree` first while its raft is launched. `open`'s fallback order is "own PR, raft PR, own worktree, raft worktree", or the author states why the own worktree comes later. G5 says "else its raft's worktree folder", so adding the issue's own worktree as a fallback extends G5. Showing it in the pane needs no decision.

Recommendation:
- Show an issue card's own worktree: the worktree that has its own PR's head branch checked out, else c0117's `state.worktree` while it runs.
- Add a server.spec case where the fixture's `facts.worktrees` holds `prep-runs` and f0021's pane model carries that path.
- Add a page.spec assertion that the issue pane's worktree row shows it.
- Add a row "an issue's own worktree is never shown", killed.
- If the author prefers to leave it out, escalate to the user: (a) the above, about 15 lines and 2 assertions; (b) a `Scope decision` that issue cards under design show no worktree, with G11's wording corrected.

Lesson: z-design/never-narrow-captured-scope

### F3 [high] The G11 cases test one open PR at one moment: six plausible wrong lays pass every spec, two of which lose most real prep PRs or drop issue PRs after 60 s
Where:
- server.spec.luau:365-379 (one `state()` after the first gh answer; only an `OPEN`, non-draft issue PR)
- server.spec.luau:523ff (the gh failure case asserts only `R0020.pr`)
- page.spec.luau:173-190 (only the raft's `pr` is set, never its `checks`)
- c0121.md:345 (the one G11 row: N74 to N76)

Evidence (each mutant on the replayed raft, one at a time):

| mutant | result | what the board does |
|---|---|---|
| **I4** `e.pr.state == "open"` (drafts excluded; gh says `OPEN` for drafts, so this is an easy slip) | server **27/0** | 4 of today's 9 correct prep PRs are drafts (#266, #260, #259, #255): their cards say "no PR" |
| **I10** lay once, at the first gh answer (`if data and laidFor == nil`) | server **27/0** | the first rebuild (60 s) makes a fresh model, so every issue PR disappears until restart |
| **I3** keep issue PRs when gh fails (`if data and laidFor ~= gen`) | server **27/0** | the card shows a stale PR and checks while the status line says "checks unavailable"; the raft half of the same rule is pinned |
| **I5** oldest open PR (`<`) | server **27/0** | a re-prep's new PR loses to the abandoned one |
| **I6** no leading boundary (`{i.id}[^%w]`) | server **27/0** | `xf0021` matches f0021 |
| **I11** page `checks: (raft && raft.checks) \|\| issue.checks` | page **10/0** | the issue's own PR is shown with its raft's checks |

Failure scenario: an executor writes I4 or I10, and AC2 passes. The served board then shows no PR for most cards under design (I4), or shows them for a minute and never again (I10). G11's outcome is missing while the gate is green.

Critique: the encode-once cache got cases across rebuilds, gh changes and failures (rounds 1 to 3). The lay is a second cache keyed on the same generation and got none. The tempting fix is one case per survivor. The rule is the generation: test the lay at every event the generation moves on.

Consequences: the fixture needs a gh stub whose answer changes between calls; the server cases already have one (`ghOut`). The page's model needs `checks` on the raft as well as on the issue. A clock jump of 61 s makes a rebuild without a key change.

Recommendation:
- server.spec, in the G11 case or a new one:
  - Add a draft issue PR (`isDraft: true`) on a second issue, required on its card.
  - Add two open PRs for f0021, the higher number required.
  - Add a title `"tracker: prep xf0021 …"`, required on no card.
  - Then advance the clock 61 s and require f0021's PR again after the rebuild.
  - Then let gh answer with f0021's PR merged and a new open one, and require the new one on the next poll.
  - Then make gh fail and require `f0021.pr == nil`.
- page.spec: give R0020 `checks = { state = "passing" }` and keep asserting "#12 open, checks failing".
- Rows: I3, I4, I5, I6, I10 and I11, each killed. Prefer behaviour over source pins.

Lesson: zz-test/seed-every-enumerated-case

### F4 [low] Stale or inconsistent text
Where and Evidence:
- c0121.md:90 (§2): `serve.GH_ARGS` lacks `title`. The code (serve.luau:264), §5 (:129) and guard.spec's argv pin all have it.
- c0121.md:96: `parsePrs` returns `{ pr, checks }`. The code's `PrEntry` adds `title`.
- serve.luau:211: the comment lists the gh fields without `title`.
- c0121.md:421, 427, 428, 429: the history now says the prototype tip was a1cdbcf8 "after design review 011" and "stays a1cdbcf8" in rounds 2 and 3. a1cdbcf8 is round 4's commit (`git log -3`: 8ffccf92 is round 1's). The old texts were rewritten wholesale (`git diff 87afeb9e~1 87afeb9e -- c0121.md`, the `-`/`+` pairs at its lines 120 to 133).
- c0121.md:430: round 4's entry gives no spec counts on the prototype. It should give page 10, server 27, guard 19 passed, as measured here.
- board.html:156-157: the renderer's comment still says "the control characters and spaces a browser ignores inside a scheme", which round 4 corrected in §6.
- c0121.md:190: the Mutation check paragraph says the second re-prep's regions are covered by N52 to N76. Once F3's rows are added, name the issue-PR lay among them.

Recommendation: fix each one, and restore the history lines to the shas they had (8ffccf92 for rounds 1 to 3).
Lesson: z-design/restated-rules-move-together

Candidate lesson (for the lead): zz-review or z-design: a rule that matches free text written by people (a PR title, a commit subject) is run once against today's real corpus (`gh pr list`, `git log`) before it is specified, and the false matches it finds go into the fixture. Check: has the matching rule been run on today's real titles, and does the fixture hold a real title that names two items?

Verdict: changes
