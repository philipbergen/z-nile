# Review 001: c0280 (design mode)
Inputs: prep worktree `prep-provenance-who-from-git` at 5b310d9b with its uncommitted `c0280.md`, `check.sh`, `acceptance/provenance-cases.spec.luau`, `acceptance/who.spec.luau` (both byte-identical to the prototype's), `experiments/mutants.py`, `harvest.md` (empty); prototype `proto-c0280` at 12226c96 (base `origin/proto-c0263-raft` fb3bb794, the base c0263's prepared design names); c0263's held prep `origin/prep-ticket-provenance` 0a5813cb (`c0263.md`, `experiments/split/c0282/design.md`, `experiments/split/c0284/design.md`); captures of c0280, c0282, c0283, c0284; origin/main 3eaa2a65.
Runs (all through `./zn run --time`): the two sequestered specs on the prototype (13 passed, 0 failed); `./zn who` on real ids in the prototype worktree (c0001, c0005, c0010, c0040, c0117, c0120, c0115, c0121, f0020, f0100, f0126, R0010, R0052); probes in a scratch clone of `proto-c0280` (`--shared`, origin repointed to a scratch bare repository, commits as `@example.invalid`); nine unlisted mutants R1 to R9 with a scratch runner of the same mechanics as the prep's `mutants.py` (one text replaced, the spec run from z-nile's home, the file restored; `git status` of the prototype empty after every run).

### F1 [high] "Each status change" is read only from commit subjects that name the item, so `prepared`, `active` and a raft's moves of its members never print (a captured outcome reworded away)
Where: Solution bullet ("each status change (the author of its `tracker: <id> <status>` commit and an agent trailer)"); Design, Behaviour 3 (`statuses`, `unblocked`); AC3; prototype `provenance.select`.
Evidence:
- The capture (`./zn capture c0280`, 372d2253) says: "./zn who <id> prints a ticket's history, oldest first: the Author …, each status change, the merge, …". c0263's prepared Q1 (origin/prep-ticket-provenance `c0263.md`, line 29) says: "what git knows (the idea's author, who made each status change) is read from history by `./zn who`". No `Scope decision` narrows it.
- On main, the subjects of that form are `git log --format=%s origin/main | grep -E '^tracker: [cdfR][0-9]{4} \S+$' | awk '{print $3}' | sort | uniq -c`: 111 `preparing`, 22 `new`, 1 `members`. There is no `prepared` and no `active`. Those arrive by the prep PR's squash (`tracker: prep c0117 … (#117)`) and by `tracker: ready R0052 …`.
- c0117: the `status:` word after each document commit (`git show <sha>:<path>`) goes new (da8b9acc), preparing (aba5c429), prepared (6e719b0d, prep PR #117), active (238625e9, ready), then into `done/` (e8c832ff). `./zn who c0117` on the prototype prints `unblocked`, `status:preparing`, `rafted`, `delivered` and `merged`. The `prepared` and `active` changes are missing.
- f0100 changes its word ten times: preparing by `tracker: new raft R0035`, new by `tracker: R0035 new`, preparing by `tracker: R0035 preparing`, prepared by #89, preparing, new, preparing by `tracker: R0035 preparing`, prepared by #106, active by the ready, done by #114. `./zn who f0100` prints two of them (`status:preparing`, `unblocked`). The raft's give-back `tracker: R0035 new` (28244e15, which changes f0100's document and three siblings') is not an `unblocked` for f0100. c0282's hand-off does count that event ("a raft's move: each issue it changes").
- Any word prints: for R0065, 409ec67b `tracker: R0065 members` (it changes four members' `raft:` and the raft's document) is a `status:members` line under Behaviour 3's rule.
Critique: The tempting fix is to add more subject shapes to the pattern: the ready, the prep squash, the raft moves. That list grows with every command (c0283's approve, `release`, `recombine`) and still misses a squash whose subject is the PR's title.
Consequences: Reading the document's own status word after each commit catches every change, whatever the subject, in the same `git show` per commit that `raftAt` already makes. Four things follow:
- A `release` give-back (`tracker: release R0083`: preparing to new, or to prepared) then reads as a status change. Q5 ("`release`'s give-back is not a recorded event") rules out showing it as `unblocked`.
- A restamp (same word, new suffix) is no change.
- c0282's coverage of `unblocked` by a record change in the same commit still works per commit.
- The capture's add is the idea, not a status change. The board needs the word per commit too (F6).
Recommendation:
- Derive `statuses` from the document's `status:` word (the part before the first `-`, as `history.luau`'s `stateOf` reads it) after each document commit of the life. Make one entry at each commit where the word differs from the one before, with the actor by Behaviour 2. A word of `new` after another word is `unblocked`, unless the same commit changed the record. The move into `done/` stays `delivered`. Read the word together with `raft:` in one front-matter read per commit (`who.raftAt` returns both).
- Add who.spec fixture cases:
  - a prep-PR-shaped squash with an agent trailer that moves the word from preparing to prepared (`status:prepared  agent:… (from git)`);
  - a ready commit that moves the document to `active/` with `status: active-…`;
  - a raft give-back `tracker: R0011 new` that changes a member (`unblocked` on the member);
  - a restamp that keeps the word (no line);
  - a `tracker: R0065 members`-shaped commit (no status line).
  Give each a Rules row and a mutant.
- Whether a release's give-back prints, and as what, is the user's call. Escalate to the user with the options: (a) `status:<word>` with the release's author, or (b) not printed. Q5 already rules out `unblocked`.
- If the author reads "each status change" as only the `./zn status` commits, that reading is itself a scope cut. Escalate to the user with the options: (a) every change of the status word, as above, or (b) only `tracker: <id> <word>` commits. Option (b) drops `prepared`, `active` and every raft move on main: `who` would show two of f0100's ten changes.

### F2 [high] A life that starts at the 2026-10-05 compaction, or whose first `done/` add was cut away, gets a false idea, rafter, delivery and merge, and `who` drops the marker `capture` prints
Where: Behaviour 3 (`delivered`/`merged`: "the oldest commit that **added** (`A`) the document under `done/<id>/`", `rafted`, `idea`); Behaviours 5 and 6 (`who.life` discards `trail.read`'s notes, and `trail.ambiguous` is never read); Edge cases ("a life that starts at a compaction commit is cut there"); the Rules row "the delivery is the first commit that added …"; E6.
Evidence (`./zn who <id>` in the prototype worktree at 12226c96):
- For c0001, c0005 and f0020, all four entries are a38f91f9 `tracker: compact ids (#64)` (author Phil, with an Opus trailer). For c0005: `2026-10-06 03:11  idea  human:Phil (from git, first add)`, `rafted  agent:claude-opus-5-5 effort unknown (from git)  raft=R0002`, `delivered  agent:claude-opus-5-5 …`, `merged  human:Phil (from git)`. The compaction renumbered 84 issues and 28 rafts (`grep -cE '^[cdf][0-9]{4} ' z-nile/compaction.txt` gives 84; `'^R[0-9]{4} '` gives 28). Every done one answers like this.
- c0010: the compaction rewrote its document in place (`M`), so the first `A` under `done/` left in the cut life is R0048's root move (c5b436ca, `tracker/` to `pickman/`). The output is `2026-10-06 03:11  rafted …`, then `2026-10-25 05:26  idea … (from git, first add)`, `delivered` and `merged` at R0048: the rafter comes before the idea. Its real delivery was `R0010: Foundation (#1)`. c0040 is the same, with R0043 (05b058ea) as its delivery.
- Nothing in the output says that history before a38f91f9 is not followed. `./zn capture c0005` does say it.
- The mutant "delivered newest done add" (applied alone) survives both specs (reviewer's R7). In a scratch clone it makes f0100 print `2026-10-25 05:26  delivered …` and `merged …` (R0048's root move) instead of `2026-10-22 20:47` (#114). E6 calls this mutant "equivalent alone". That is true only of a fixture with no root move; real done items have two adds under `done/`.
Critique: The design takes `trail.read`'s cut as the item's life, then reads "the first add under `done/`" inside it. Both the cut commit and a root move are adds under `done/`. The tempting fix, "skip the cut commit", still leaves c0010 and c0040 delivered by the root move.
Consequences:
- If nothing is derived here, old done items have no `delivered`/`merged` (the "where possible" of the back-fill decision), and the marker makes that visible.
- A delivery rule that ignores root moves has to define a move between roots. c0118's `doneAt` already does ("A move between roots is no arrival … a re-add is no arrival", `history.luau`). Restating that rule in `provenance` gives one fact two rules (zz-arch, one reader per format; z-design/restated-rules-move-together).
- An item first captured in a commit that also changed the map would still get its idea from that commit. That is rare, and the marker covers it.
Recommendation:
1. `who` prints `trail.read`'s notes and `trail.ambiguous` the way `capture` does: a first line, or a marker on the `idea` entry (`(history before <sha> not followed: it changed <file>)`, `(ambiguous: two items held this id at once)`). Behaviour 5 and the zz-rules row say so.
2. Nothing but the marked idea is derived from the commit that starts a cut life.
3. The delivery is the item's first arrival in `done/` in its life, by c0118's rule: a move between roots and a compaction's re-add are no arrival. Share that rule with `history.luau`'s `doneAt` instead of restating it. A life with no arrival has no `delivered`.
4. Add who.spec cases, each asserting the marker and no `delivered`, `merged` or `rafted` from the compaction:
   - a done item re-added by a compaction commit that changes the map and reuses a done id (the lesson's fixture shape);
   - a done item moved between roots after its delivery (this kills R7 and the cut-start delivery).
   Give each a Rules row, and correct E6's "equivalent alone".
Lesson: zz-rules/item-history-spans-moves-and-compaction

### F3 [high] `./zn who <R-id>` exits 1 on every raft that has a ledger, because a raft's `spend.md` is a roll-up that `ledger.parse` refuses
Where: Behaviour 5 ("It takes an issue or a raft id; refuses … a `spend.md` that does not parse"); `cmd.who`; the Test plan has no raft case.
Evidence:
- `./zn who R0052` prints `who: z-nile/.tracker/rafts/done/R0052/spend.md does not parse (not a spend row (numbers): | issue | type | emergent | +lines | -lines | minutes | tokens |)`. pickman's R0010 fails the same way.
- `git ls-files '*/.tracker/rafts/**/spend.md' '*/.tracker/rafts/*/spend.md'` lists 70 files, and all 70 are the roll-up (`| issue | type | emergent …`).
- The mutant "who treats a raft as an issue" (`who.life`'s kind fixed to `issues`, R5) survives who.spec: no case runs `who` on a raft.
Critique: The tempting fix, "skip a `spend.md` that does not parse", drops the refusal Behaviour 5 promises for issues.
Consequences: A raft's ledger has no phase or model, so it names no worker. A raft's idea is always a first add (`trail.namedIds` finds no id in `tracker: new raft …`). Its `raft:` is empty, so it has no rafter. Its delivery is its own move into `done/`. The design should state all four.
Recommendation:
- For a raft, read no ledger, or read the roll-up with a reader of its own if a worker is wanted from it (one reader per format).
- State what a raft's entries are: the idea marked first add, its status changes, `delivered`/`merged`, and its stored rows.
- Add a who.spec case: a done raft with a roll-up `spend.md` and a record row prints its entries and exits 0. Add a Rules row whose mutants are the issue-only kind and a ledger read for a raft.
Lesson: zz-test/seed-every-enumerated-case

### F4 [high] `merged` names a commit that merged nothing: in a worktree before the PR merges, and in every PR landed by a merge commit. The real merge is never read.
Where: Behaviour 3 (`delivered` and `merged`: "the oldest commit that added the document under `done/<id>/` … `merged` with the commit's author alone"); Behaviour 5 (`HEAD`).
Evidence:
- True PR merges are on main: `git log --merges origin/main` lists `Merge pull request` #206, #143, #159, #190 and #152. For f0126 (raft R0053, PR #206) the prototype prints `2026-11-01 20:06  merged  human:Philip Bergen (from git)`. That commit is 4ed01582 `tracker: done R0053` on the branch (`git log --diff-filter=A -- '*/issues/done/f0126/f0126.md'`). The merge itself, 63561874 (Phil, 20:13 UTC), is never read: `git log --name-status` shows no changes for a merge commit, so trail never lists it.
- In the scratch clone, a branch with a `raft:` commit and a done-like move carrying a Sonnet trailer, with nothing merged: `./zn who c9999` prints `delivered  agent:claude-sonnet-5-5 …` and `merged  human:Philip Bergen (from git)`. zz-execute runs `./zn done` ("moves the items to `done/` and pushes the done commit") before the PR merges (Phase 6), so every raft worktree shows a merge that has not happened.
- On a squash (e8c832ff, R0052 #125) the author is `Phil <philip.bergen@me.com>` and the committer is `GitHub <noreply@github.com>`, whoever pressed merge. c0282's hand-off says "the agent that ran `done` merges its own PR, and the squash commit's `Co-Authored-By` agrees". For every agent-merged PR, `merged  human:Phil` disagrees with c0282.
Critique: "The commit that added it under `done/`" is the merge only when main takes the branch as one squash and `who` reads main. The tempting fix, `--first-parent` on `HEAD`, still prints a merge in a raft worktree.
Consequences: The merge is a fact of the mainline, so reading it needs `origin/main` (or `main`) whatever `HEAD` is. In a worktree the entry stays absent until the delivery is on the mainline, and the board (on main) gets the same answer. Git does not record who pressed merge: the merge commit's author is the PR's account.
Recommendation:
- `merged` is the first-parent commit of the mainline (`origin/main`, else `HEAD` in a checkout without one) that brought the delivery in:
  - the delivery commit itself, when it is on the first-parent line;
  - otherwise the oldest first-parent merge whose second-parent side contains it (`git log --first-parent --merges --ancestry-path <delivery>..<mainline>`);
  - none, when the mainline does not contain the delivery.
- The actor: escalate to the user, with the options:
  - (a) the merge commit's author, as today, qualified (for example `(from git, merge author)`) and stated in zz-rules as "the PR's account; git cannot tell who pressed merge";
  - (b) the squash's agent trailer, as `delivered` reads it (then `merged` repeats `delivered` on a squash);
  - (c) no actor.
- Add cases:
  - a fixture branch merged `--no-ff` whose done-like commit is older than the merge: `merged` is the merge, `delivered` the branch commit;
  - a worktree whose branch has the done move while `origin/main` does not: no `merged`;
  - the squash case, kept.
Lesson: zz-arch/history-tests-survive-squash (the converse case: a history rule built for squashes meets main's true merges)

### F5 [medium] Entries in the same minute print by kind, not by time, so an unblock can print after a later status change
Where: Behaviour 4 ("at the same minute a derived entry comes before a stored one, then the order they came in"); prototype `provenance.merge` (its rank is insertion order: the idea, every status, every unblock, rafted, delivered, merged).
Evidence:
- Scratch clone, three commits: `tracker: c9999 preparing` at 11:00:05 (Dee), `tracker: c9999 new` at 11:00:20 (Eli), `tracker: c9999 preparing` at 11:00:40 (Fay). `./zn who c9999` prints Dee's `status:preparing`, then Fay's `status:preparing`, then Eli's `unblocked`.
- Same-minute pairs exist on main: `git log --format='%ct|%s' origin/main | grep -E '\|tracker: [cdfR][0-9]{4} (new|preparing)$'`, grouped by item and minute, gives c0261 and R0030. R0030's `new` came before its `preparing` in the same minute, so `who` prints them reversed.
Critique: The captured outcome is "oldest first", and the minute in the stamp is a display unit, not the order.
Consequences: Derived entries carry their commit's time in seconds and the log's order. Stored rows carry only the minute, so the minute remains the key between a derived and a stored entry (derived first, as designed).
Recommendation: Order derived entries among themselves by commit time, then by log order (oldest first), and use the minute only against stored rows. This still holds with F1's status-word derivation. Add a provenance-cases case with a `new` between two status commits in one minute, and a mutant that sorts derived entries by kind.

### F6 [medium] The shared reader is built so that the board must show fewer entries than `who`, against c0284's capture
Where: Behaviour 6 ("c0284 passes an empty `raftAt` (the board leaves out the derived `rafted` …)"); "What the upper layers may change" (c0284 "pins that the board's equal `who`'s except for `rafted`"); AC6.
Evidence:
- c0284's capture (`./zn capture c0284`, 11fae0e1) says the board shows "the same entries ./zn who prints for it (one shared reader of the history, so the two views cannot disagree)". The exception comes from the earlier c0263 prep's text (`split/c0284/design.md`, AC9: "except for the one entry that needs a read per commit"), not from a user decision. With F1's fix, the board would also lose every status change.
- The board's life must be built exactly as `trail.read` builds it, and the interface does not say so:
  - each commit's `id` must be set to the item's id, or `trail.capture` never matches and every idea reads as a first add;
  - the `want` filter is applied after the cut;
  - the board's single `git log` over every root is not the per-item, path-limited `git log` that `trail.read` runs, and history simplification at merge commits can differ between the two.
Critique: The per-commit `git show` is what drives the cost. Accepting the exception narrows c0284's captured outcome, which is the user's call.
Consequences: `raft:` and `status:` can be read for every item in one process:
- from the patch lines of one `git log -p --unified=0` over the documents, as `history.logArgs` does (an added document's whole front matter is in its patch);
- or from one `git cat-file --batch` fed every `<sha>:<path>`.
The board could then pass the real `raftAt` and status map, and the per-item read for `who` can use the same source.
Recommendation:
- Give the reader a per-commit front-matter source that costs one process for the whole history (either of the two above).
- Export the per-item step the board needs, `who.lifeOf(commits, id, cuts)` (cut, set `id`, filter by `who.want`), so the board cannot build a life another way.
- Then AC6 says "the board passes the same `raftAt`", and c0284 needs no exception.
- If that is not wanted, escalate to the user (with c0284's prep), with the options: (a) the board shows `who`'s entries except `rafted` (and, with F1, except the status changes), or (b) one batched read as above, at the cost of one more git process per board build.
Lesson: z-design/quote-other-preps-before-promising

### F7 [medium] Three in-flight items change `trail.luau`, and c0138 replaces the very predicate that `trail.cut` extracts. The design names none of them.
Where: "What the upper layers may change, and what this layer pins" (it names only c0282, c0283, c0284 and c0263); "Where it bites"; the Regression guard; Implementation step 1 (apply the prototype diff); AC6 ("`trail.cut` is the cut `read` applies").
Evidence:
- The search ``git grep -lE '`z-nile/engine/(trail|store|who|provenance)\.luau`' origin/main -- 'z-nile/.tracker/issues/*.md' 'z-nile/.tracker/issues/*/*.md' 'z-nile/.tracker/issues/active/*/*.md'``, with `done/` excluded, finds three items that list `z-nile/engine/trail.luau` among their Touched modules: c0136 and c0138 (both active in R0068, readied at 6145abab) and c0181 (prepared, R0074).
- c0138 (`active/c0138/c0138.md`, line 47) says: "`trail.read`: a `cutsId(sha)` closure (a cut commit, and `trail.resets(trail.renames(sha), id)` …) replaces `cuts[c.sha] ~= nil` in `since`'s predicate". That is the predicate the prototype moves into `trail.cut(commits, cuts)` (`return c.doc and cuts[c.sha] ~= nil`).
- After c0138 lands, `trail.cut` given `trail.cuts(head)` still cuts at the compaction for every item the compaction rewrote in place, and `read` no longer does. That makes two definitions of a life, while c0280's `cut` case and AC6 say they are one.
- c0138's sequestered `docs.spec` pins the comment on `read` ("and renamed its id, or whose map does not parse or can't be read (`since`"). The prototype's comments on `read` and `cut` restate the old wording.
- c0136 and c0181 add names to `trail.isDoc`.
Critique: Whichever item lands second conflicts in `trail.read`. The prototype diff of step 1 no longer applies cleanly, and the executor has no rule for how `trail.cut` and c0138's per-id reset compose.
Consequences: To keep `trail.cut` pure, its caller passes only the cut commits that start this id's life (c0138's `resets(renames(sha), id)` per cut commit). The board then calls `renames` once per cut commit too; there is one compaction today.
Recommendation:
- Name c0136, c0138 and c0181 in the layer section and the Regression guard.
- Define `trail.cut(commits, cuts)` as taking only the cut commits that start this id's life. Once c0138 is in, `read` filters `trail.cuts(head)` through c0138's `resets`/`renames` before calling it, and c0284 does the same through F6's exported step.
- Write `trail.cut`'s comment in c0138's wording.
- Run c0138's `kept`, `renamed` and `docs` specs on a tree that holds both changes (the prototype rebased on R0068's branch, or with c0138's `prototype.patch` applied), whichever item lands second, and record the result.
Lesson: z-design/mutation-runner-runs-correct-variants

### F8 [medium] Stated rules have no case that fails: seven more unlisted mutants survive, and the "no history" refusal is not implemented
Where: Behaviour 2 ("A value with no email counts as an agent"; `people` is "every author email of the log"); Behaviour 3 ("A move … is one entry"; "A commit that only deletes a path of the document is skipped"; "for a `done` item"); Behaviour 5 ("refuses (exit 1) … an id with no history … and a `spend.md` that does not parse"; "It reads the **checkout's own history** (`HEAD` …)"); Edge cases ("a prep worktree's uncommitted add: `who` fails with 'no history'"); the Rules and mutants table.
Evidence:
- The reviewer's runner, run on provenance-cases and who.spec. All of these survived:
  - R1: `head = "origin/main"`;
  - R2: `people` taken from the item's own life only;
  - R3: `not gone` dropped;
  - R4: `state == "done"` dropped;
  - R6: a trailer with no email treated as a person;
  - R8: a move's two rows count as two entries (`not seen[c.sha]` dropped);
  - R9: a `spend.md` that does not parse is skipped.
  R5 and R7 are under F3 and F2.
- Probe 1 (scratch clone): an untracked `c9999/c9999.md` with a record row. `./zn who c9999` prints the record row and exits 0. `trail.read` returns an empty table, not nil, so `who.life` never fails.
Critique: Each of these is a sentence of the Design that an executor can drop while the specs stay green.
Consequences: R4 needs either a case where a non-done item's life holds an add under `done/` (a reopen, if the tracker allows one), or the Design drops the guard as unobservable. R8 matters once F1 derives statuses from commits that also move the document (ready, stop, a give-back out of `active/`).
Recommendation:
- `who.life` fails on an empty life ("no history for <id> on HEAD").
- Add cases:
  - an item with only uncommitted files (refused, nothing printed);
  - a worktree whose `HEAD` has a commit that `origin/main` lacks (R1);
  - a trailer whose email belongs to an author only outside the item's life (R2);
  - a delete-only document commit given a `raftAt` value (R3);
  - a status-changing commit that also moves the document (R8);
  - a trailer value with no email (R6);
  - a `spend.md` that does not parse (R9: refused, naming the file).
  Give each a row in Rules and mutants.
Lesson: z-design/spec-design-correspondence

### F9 [low] `provenance.fromTrailer` is an exported function that no code calls
Where: Behaviour 2, AC1, Interfaces. `git grep -n fromTrailer -- z-nile | grep -v '^z-nile/tests/'` finds only its definition (`provenance.luau:434`).
Critique: AC1 pins a rule the command never applies. `fromCommit` parses trailer values on its own, so the two rules can drift apart: a name-less value is nil in `fromTrailer` and is skipped by `fromCommit`.
Consequences: none.
Recommendation: Either `fromCommit` calls `fromTrailer` on each `Co-Authored-By: <value>` line (one rule), or `fromTrailer` leaves the interface and its rule is pinned through `fromCommit` cases.

### F10 [low] E1's scratch-repository probe is not recorded as run through `./zn run`
Where: Unknowns & experiments, E1 ("a scratch repository under `$TMPDIR` … and `git log …`").
Critique: AGENTS.md says every probe runs through `./zn run --time`. E2 and E6 say how they ran; E1 does not.
Consequences: none.
Recommendation: Record that E1 ran through `./zn run --time <s>`, or rerun it that way, as E6 does.

## Lesson candidates (reviewer; for the lead to place)
- z-design: run a history-derived answer on the real tree's hard items before calling it proven. Rule: run each derived answer on a pre-compaction done item, a done item moved between roots, a PR landed by a merge commit and a raft id. Why: E2 ran `who` on c0117 alone, which had none of these shapes, and four high findings appeared on the first other real ids tried. Check: has each derived field been printed for those four kinds of real id?
- zz-test: an "equivalent alone" mutant must be equivalent on real history, not only on the fixture. Why: E6 called "delivered newest done add" equivalent, but real done items have a second `done/` add (a root move). Check: is there a real history in which the single mutant gives another answer?
- zz-arch: read a fact the document holds (`status:`, `raft:`) from the document at each commit, never from commit subjects that name it. Why: a PR squash, a raft's move and `release` change the same field under other subjects (F1). Check: which commands change this field, and under which subjects?

Verdict: changes
