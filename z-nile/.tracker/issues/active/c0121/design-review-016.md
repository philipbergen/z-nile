# Review 016: c0121 (design mode)
Inputs: prep-board-server2 496aa6b1 (c0121.md whole, check.sh, acceptance/ specs, harvest.md, design-review-015 and design-refute-015, `git diff 87afeb9e 496aa6b1`). proto2-c0121 is at 3ae84284 (`git ls-remote origin refs/heads/proto2-c0121`); `git diff 3ae84284~2 3ae84284 -- z-nile/engine/` is round 5's fix (`serve.firstId`, `PrEntry.branch`, `cache.worktrees`, `Issue.worktree`, the issue pane's worktree row). origin/main is 0f34b70b after `git fetch origin main`.
Scratch clone: `.worktree/prep-board-server2/.cache/r016/repo`, made by `/private/tmp/claude-501/-Users-philipbergen-code-pickman/1710de1d-709d-43fa-afde-dbe194852ce3/scratchpad/r016/setup.sh`. That is round 5's script with PREP 496aa6b1 and tip 3ae84284. In it, `main` is origin/main plus the prep's c0121 folder, and `raft` is main plus an empty start commit plus step 1's apply. The prototype worktree was not touched (the author's full gate runs there).
Mutation runner: `/private/tmp/claude-501/-Users-philipbergen-code-pickman/1710de1d-709d-43fa-afde-dbe194852ce3/scratchpad/r016/mut.py`, output in `mut.out` beside it. It applies one mutant at a time on the clone's raft branch and restores the file after each (`engine clean` at the end).
Real-data probe: `.cache/r016/repo/r016-probe.luau`, the real `serve.start` with stub effects on the clone's tracker. Its gh stub prints today's real `gh pr list` output (`.cache/r016/gh.json`, 200 entries, read-only gh). Its facts are the clone's, with `worktrees` replaced by the main checkout's real `git worktree list --porcelain` (`.cache/r016/wt.txt`, 69 worktrees). `probe-mut.py` runs the same probe under a mutant.
Every probe ran through `./zn run --time …`.
Round 6 of the second re-prep (an extra round the user approved). Dropped from review-015: F1, F2, F3, F4. Each fix holds as far as it goes; the evidence is below. What round 5's F1 and F3 cases left out is judged in F1.

## What holds (run)
- **Step 1 on today's main (0f34b70b).**
  - `merge-base --is-ancestor 3ae84284 origin/proto2-c0121` succeeds.
  - Every non-new watched path exists, and `serve.luau` does not.
  - `git log --first-parent 3993dca2..origin/main -- <watched>` prints nothing.
  - The apply exits 0 with all 8 paths clean, and `git diff 3ae84284 HEAD -- <8 paths>` is 0 lines.
  - `overrides.patch` is identical to the prototype's `docs.spec` diff, and that diff has not changed since fa44f524.
- **`./zn check c0121` on the replayed raft: 7/7** (AC7 reads origin's main from the clone). c0120 `check-paths.spec`, run from the clone's `z-nile/`: 4 passed, 0 failed.
- **c0117's contract greps** on origin/main's `dispatcher.luau`. It is `cmp`-equal to 3993dca2's: c0279 (R0089, #277) changed the dispatch-cli spec, not the dispatcher.
  - grep 1: lines 73 and 1848.
  - grep 2: line 986 only.
  - grep 3: failed 8, lost 1, missing 1, stopped 1, tripwire 7, with the nil clears at 1790 and 2044.
- **Specs on the clone**: guard 19/0, server 28/0, page 10/0, docs 3/0, cli 8/0. c0118's promoted `page.spec` passes 15/0, so the per-field fallback holds.
- **The rule on today's real PRs** (`r016-probe.luau`):
  - 9 issue cards get a PR. Each is the item's own: c0132 #175, c0152 #165, c0166 #177, c0257 #243, c0261 #259, c0262 #260, c0263 #266, c0264 #265, c0265 #255.
  - 8 of them get their prep worktree. c0257's branch `omarchy-board-app` has none, so its row is empty.
  - #260 ("WIP: c0262 … held until c0248 and c0260") goes to c0262 only.
  - #167 (`tracker: raft R0062 … (c0141's record)`) and #172 (`R0061: c0131 …`) go to no issue card.
  - `open c0248`, `open c0141` and `open c0131` answer 400. After a 61 s rebuild, still 9 cards have a PR.
- **Title spellings** run through `serve.firstId`:

  | title | result |
  |---|---|
  | `tracker: raft R0083 c0118 board` | R0083 (no issue card) |
  | `R0083: c0118 board` | R0083 |
  | `c0118: board` | c0118 |
  | `unfold c0121 from R0084` | c0121 |
  | `WIP: c0262 x` | c0262 |
  | `tracker: capture c0280 c0281` | c0280 |
  | `[c0121] fix` | c0121 |
  | `tracker: prep C0121` | nil |

  The brief asked which card a raft PR that names an issue second gets. It gets none: the R-id comes first. The raft's card takes only its launched branch's PR (`raft.pr`), so a rafting PR shows on no card, which is correct.
- **Over all 200 real titles**, the text before the first id is one of:
  - `tracker: prep ` (88)
  - none, an `R0088: ` or `c0257: ` title (52)
  - `tracker: raft ` (32)
  - `tracker: ` (10)
  - `tracker: unfold ` (4)
  - no id at all (4)
  - eight one-off shapes

  The first id is the PR's own item in every shape except one. A capture's PR (`tracker: capture workers carry rafts to merge (c0260-c0265, …)`, #258, merged) would put a capture of eleven items on c0260's card while it is open. That is the safe direction and is not a finding.
- **Round 5's mutants**, re-run (each killed on an assertion):

  | mutant | result |
  |---|---|
  | N74 (merged counts) | server 26/2 |
  | N75 (any id) | server 26/2 |
  | N76 (raft's PR first in `open`) | server 27/1 |
  | N77 (drafts excluded) | server 26/2 |
  | N78 (oldest) | server 26/2 |
  | N79 (first generation only) | server 26/2 |
  | N80 (kept when gh fails) | server 26/2 |
  | N81 (no worktree) | server 27/1 |
  | N82 (an id matched as a prefix) | server 26/2 |
  | N83 (raft's checks first) | page 9/1 |
  | N84 (no issue worktree) | page 9/1 |

  Also killed:
  - a literal "starts with" (`^[cfdR]…`): server 25/3
  - the last id of the title: server 26/2
  - laid only on a rebuild: server 25/3
  - the issue's worktree kept when gh fails: server 26/2
  - the raft's worktree laid as the issue's: server 25/3
  - the page's raft PR first: page 9/1
- **Unchanged regions.** The retry 409, encode-once splice, generation, gh version and signature, and link renderer were not changed since round 5. Their specs pass on today's main, and no watched path moved. N52 to N73 were not re-run this round, because round 5 ran them on 0b0a4017.

### F1 [medium] Four plausible wrong lays still pass every spec. Two of them put another item's PR, or a closed PR, on today's real cards
Where:
- server.spec.luau:46-60 (GH_JSON has no title that starts with a raft id and then names an issue, no CLOSED PR titled for an issue, and no `xf0021`-style title)
- server.spec.luau:111-114 (the `facts` stub returns the same two worktrees at every build)
- serve.luau:218, 441, 419
- c0121.md:130 (§5: "A merged or closed PR never hides its raft's"; "a raft id never takes a PR")
- c0121.md:347 (the row's mutant list)

Evidence (`mut.out`, each alone on the replayed raft):

| mutant | specs | what the board does (`probe-mut.py` on today's real PRs) |
|---|---|---|
| **J1** `firstId` skips raft ids (`[cfd]` for `[cfdR]`, the shape of `store.isIssueId`, the reader a "one reader per format" author reaches for) | server **28/0**, guard **19/0** | c0131 (done, in R0047) gets **#172**, R0061's draft PR, with R0061's worktree. c0141 gets **#167**, a rafting PR. `open c0131` and `open c0141` open them. This is round 5's F1 misattribution again. |
| **J5** `e.pr.state ~= "merged"` (closed PRs count) | server **28/0** | c0118, c0120 and c0121 show their closed `impl-` PRs (#122, #100, #123). d0149, a member of R0066, shows **#127 closed**, which would hide R0066's PR once R0066 launches. That breaks §5's own "a merged or closed PR never hides its raft's". |
| **J7** the branch-to-worktree map built at the first build only | server **28/0** | a prep worktree made after the server started (the server lives about three days) never shows on its card |
| **J3** `firstId` without its leading frontier | server **28/0** | `xf0021` names f0021; there is no real title like it, so this one is minor |

Failure scenario: the carried `serve.luau` is right. It is a new file, so step 1 applies it whole, and that is why this is medium, not high. The cases are promoted at `done` as the regression guard for G11. A later edit that reuses the issue-id reader (J1), or reads "merged or closed never hides its raft's" as "merged never…" (J5), stays green. The served board then shows a raft's PR on a member card, or an abandoned closed PR, which is what G11 and round 5's F1 removed.

Critique: round 5's F1 Recommendation listed `"tracker: raft R0020 regrouped (f0022's record)"` and `"R0020: f0021 …"`, each on no issue card. Its F3 listed `"tracker: prep xf0021 …"`. The refute added the capture-PR and `f00210` cases and left these out. This is the third round in which the fixture is built from the cases a review names instead of from the real producer's title shapes. The lesson the author added this round says "the false matches it finds go into the fixture". The tempting fix is two more PRs in GH_JSON. That fixes these, and the next shape is missed in the same way.

Consequences:
- The fixture should hold one title of each shape the real corpus has:
  - a prep PR
  - an `R…: <member> …` raft PR
  - a `tracker: raft R… <member>` rafting PR
  - a closed prep PR
  - a capture naming several ids
  - a WIP PR naming later ids
- GH_JSON is shared by the state, open and encode cases. Each new PR must keep their assertions:
  - give the new PRs branches no raft launches;
  - give each a number that does not outrank f0021's #15 unless that is the point of the case.
- A changing `facts.worktrees` needs the stub to read a variable, as `key` and `ghBody` already do.

Recommendation:
- server.spec GH_JSON gains:
  - `"R0020: f0022 Running"`, OPEN, on a branch that is not `R0020-alpha`, so `parsePrs` keeps #7 for the raft. Require it on no issue card.
  - `"tracker: raft R0030 regrouped (c0098's record refreshed)"`, OPEN. Require `c0098.pr == nil`; the open case's `open c0098` → 400 then also pins it.
  - `"tracker: prep f0022 Reviewed again"`, CLOSED, with a number above #11. Require `f0022.pr == nil`, and require `open f0022` to still open #7.
  - `"tracker: prep xf0021 …"`, OPEN, highest number. Require f0021 to keep #15.
- The `facts` stub returns a worktree list the case can change. Add one case: after a rebuild with a new `{ path = …/wt/runs, branch = "prep-runs-again" }`, f0021's card carries that path.
- Rows: J1, J3, J5 and J7, each killed.
- In §5, say that the fixture's titles are taken from the real `gh pr list` shapes, and list them. The next author then extends the list from the corpus, not from a review.

Lesson: zz-test/seed-every-enumerated-case

### F2 [low] The issue pane's worktree row can show the raft's worktree before the issue's own, and no case can tell
Where:
- board.html:310
- page.spec.luau:166-190 (R0020 has no worktree: `facts.worktrees = {}`)
- design-refute-015 F2 ("shown on the card before the raft's")

Evidence: J10 (`raft && raft.worktree ? raft.worktree : issue.worktree ? …`) passes page **10/0**.

Failure scenario: a member of a launched raft whose own PR is open. One case is a re-prep of a member while its raft's branch and worktree still exist. The card shows the raft's worktree, while its PR row shows its own PR. The two rows disagree. This is rare, hence low.

Recommendation: give page.spec's R0020 a worktree (`facts.worktrees = { { path = "/w/R0020", branch = "R0020-alpha" } }`). Require the f0021 pane to show `/w/prep-runs` and not `/w/R0020`. Add row J10.

### F3 [low] Stale or inconsistent text
Where and Evidence:
- **The tip shas.** c0121.md:424 ("3ae84284 after design review 011") and :431 ("the prototype tip stays 3ae84284", round 2) are 8ffccf92 in history (`git log` on proto2-c0121: 8ffccf92 is design review 011's commit).
  - This is the third time a tip change rewrote these two lines. At 87afeb9e they read a1cdbcf8, and at 580e9b4a 7c2b067a (`git show <c>:…/c0121.md | grep -o 'stays [0-9a-f]\{8\}'`).
  - Round 5's F4 fixed :430 and :432, but the replace that moves the tip still reaches :424 and :431.
- **"Starts with" against "first id".** c0121.md:35, :130, :237 (the case name) and :398 (G11), and serve.luau:215's comment, say the title "starts with the issue's id". The rule is the title's first tracker id: `tracker: prep c0121 …` does not start with `c0121`. The examples beside it contradict the wording. A literal reading is caught (server 25/3), so this is clarity only. Say "whose first tracker id is the issue's".
- **Text still about rafts only.**
  - c0121.md:46 (Solution) "fills each raft's reserved `pr` and `checks`", and :60 (data flow) "fill rafts' pr/checks from the gh cache". Both now apply to issues too.
  - c0121.md:65's module table lists no `firstId`.
  - :66 and §2's `board.luau` lines (:102-104) do not list `Issue.worktree`.
  - :133 "The PR and checks are laid on each time from the cache" contradicts §5's "laid on once per generation" for an issue's PR.
- **The acceptance criteria.** AC2 (c0121.md:355) says "its own open PR and checks". It leaves out drafts and the worktree, which are G11's outcome and what round 5's F2 restored. AC3 (:356) leaves out the issue's worktree on the card.
- **The cited caveat.** c0121.md:180's "apart from c0117's load-sensitive `dispatch-cli.spec`" predates c0279 (R0089, #277), which fixed that spec on main. Cite the next full gate's result instead.
- **The harvest.** harvest.md maps design-review-015 F1 to `z-design/never-narrow-captured-scope`, but that finding's `Lesson:` was `zz-test/seed-every-enumerated-case` (F1 was a misattribution, not a scope cut).
- **The zz-rules board row** (the prototype's `--serve` sentence) says "shows each card's PR and checks". It never says that an issue's PR is found by the first id of its title. A person who titles a PR otherwise sees "no PR" and has no way to know why.

Recommendation:
- Fix each one by hand.
- Give the prototype's tip one home: step 1 and G8 name it, and history entries name the sha of their own round. Change it with an edit of those two lines, never a whole-file replace.
- Add half a sentence to the zz-rules row: "an issue's PR is the newest open or draft PR whose title's first id is the issue's".

Lesson: z-design/restated-rules-move-together

Candidate lesson (for the lead): zz-test or z-design: a rule over free text gets its fixture from the corpus's shapes, not from the cases a review lists. Classify the real items by the text around the matched token (here, what precedes a title's first id) and put one of each shape in the fixture. Check: does the fixture hold one item of every shape the real corpus has, including the closed and the raft-first ones?

Verdict: changes
- F1 [medium]: fixture gaps leave J1, J3, J5 and J7 green. J1 and J5 put wrong PRs on today's real cards. The carried code is right, so this does not make the delivered result wrong.
- F2 [low]: the order of the issue's and the raft's worktree is unpinned (J10).
- F3 [low]: stale text. The tip-sha history was rewritten a third time, "starts with" contradicts first-id, the Solution, data flow, types, AC2 and AC3 are partly stale, and there are small harvest and doc gaps.
- No high finding remains. F1 is a medium, so the verdict is changes. Once F1's cases and rows are added, nothing in this round blocks.
