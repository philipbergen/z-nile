# Review 008: c0263 (design mode)
Inputs: prep `prep-ticket-provenance` at a4de4bc4 (re-prep 76cd0a1d): `c0263.md`, `check.sh`, `acceptance/{provenance,publish,record}.spec.luau`; prototype `proto-c0263-raft` at c1e941f8 (base 0ea4a484; its three spec copies are byte-identical to the sequestered ones); origin/main 99e8a74a (no touched file and nothing in `z-nile/tests/lib` changed since the prototype's base, so the prototype's runs hold on today's main). Rounds 003 to 007 were read for history only.
Capture: `./zn capture c0263` prints `(no capture commit: first add)`, so it is not a confirmed capture. Judged from history: the first add (081392e0) holds the Problem, and the current Problem keeps it word for word, adding only `Decided with the user` lines and one `Scope decision (user, 2026-11-08)` line. Every outcome the split moved out is in the Problem of c0280, c0282, c0283 or c0284 (read on this branch). Each outcome this layer keeps (the record, `./zn record`, the publish rule, audit, the union) has a Checked AC. No scope finding.
Runs, all in scratch clones of c1e941f8 under the session scratchpad, with each clone's `origin` pointed at a throwaway bare copy, every probe through `./zn run --time`:
- (a) The clean prototype, 17 spec files the design did not run: 118 passed, 0 failed.
- (b) Five combined mutants on record.spec and publish.spec: 12 passed, 0 failed, so every one of them survives.
- (c) Lune probes of the prototype's `provenance.luau`, and a git probe of `merge.directoryRenames`.

### F1 [high] Nothing pins the live actor's adapter. An implementation that never reads `ZN_ACTOR` or the agent session passes check.sh and records a bot's work as the user's
Where: Solution, "The live actor"; Behaviour 2, last sentence; The split ("Each wiring is checked through its caller (AC3 to AC6)"); Usability ("never the user as a bot's work"); Edge cases ("A malformed `ZN_ACTOR`/`--actor` … refuses before it changes anything"); check.sh AC1's label ("the live inputs and the resolution order … hold"); Rules and mutants row 2 (its mutants are on the pure `resolve` only); prototype `main.luau:391-405` (`liveActor`).
Evidence: run (b) changed `liveActor` to `agent = false` and `provenance.resolve(<flag>, nil, hint, name)`, so `ZN_ACTOR`, `CLAUDECODE`, `AI_AGENT` and `CLAUDE_EFFORT` are never read. With the four mutants of F3, F6 and F7 also applied: `12 passed, 0 failed, 2 spec files`. In record.spec, `ZN_ACTOR`, `CLAUDECODE`, `AI_AGENT` and `CLAUDE_EFFORT` appear only in the `HUMAN` table (:18-19), which sets them all to `""` for every call. The one `record` call without `--actor` (:135) asserts a row count, never the actor. This reviewer's own shell has `CLAUDECODE=1`, `AI_AGENT=claude-code_2-1-319_agent` and `CLAUDE_EFFORT=xhigh`: an agent session is exactly where c0250's workers will call `record`. Two more gaps:
- E5 (which variables mark a session) is the only evidence for the hint, yet it moved to c0280's and c0283's excerpts. Nothing records what the `grok` and `agent` CLIs that `.models.toml` names set.
- `experiments/split/c0283/design.md:11` defines an agent session as `CLAUDECODE` or `AI_AGENT` *or `ZN_DISPATCH`*, while this layer's hint reads only the first two: one rule with two definitions in one raft.
Critique: AC3's "refuses … a bad actor" is met by an implementation that ignores `ZN_ACTOR=none` and publishes under the git name. The Usability promise is unguarded where the command will mostly run. The tempting fix is one case with `CLAUDECODE=1`, which still leaves `ZN_ACTOR`, `AI_AGENT` and the effort unpinned, and leaves each source's value indistinguishable from the others.
Consequences: each source needs a case whose value differs from every other source's, so a mutant that reads the wrong one shows. Unifying the agent-session test with c0283 means a pure function over the environment that both layers call, and then it must be decided whether `ZN_DISPATCH` alone (a dispatched step before c0282 sets `ZN_ACTOR`, or a `grok` step that sets no `CLAUDECODE`) counts as an agent session.
Recommendation: add record.spec cases through `./zn record` that assert the actor cell of the row on origin:
- `CLAUDECODE=1 CLAUDE_EFFORT=high`, no flag: `agent:unknown effort high`, not `human:<fixture name>`;
- `AI_AGENT=x` alone: `agent:unknown effort unknown`;
- `ZN_ACTOR=agent:grok-4-7 effort xhigh` with `CLAUDECODE=1`: the `ZN_ACTOR` value;
- `--actor human:Ann` with `ZN_ACTOR` set: the flag;
- `ZN_ACTOR=none`: refused, origin's tip unchanged;
- a plain environment: `human:<fixture git name>`.

Give each adapter mutant its own row. Move the hint into the pure module as `provenance.hint(env)`, with `ZN_DISPATCH` decided and stated, and write in the c0283 hand-off that its refusal calls the same function. Keep E5 in this document and add what `grok` and `agent` sessions set: a bounded `env` probe from each, or, if that can't be run, the fallback that `ZN_DISPATCH` counts as an agent session.
Lesson: z-design/live-defaults-checked-in-their-session (written by this issue's round 001; its "How to apply" is "run the command in each session that runs it and read what it records"), zz-test/kill-mutants-where-the-value-is-built, zz-test/pin-call-site-arguments

### F2 [high] (repeat of design-review-005 F13's mechanism) `parse` still skips every line that doesn't start with `|` and keeps a five-cell row, so AC2's "refuses every malformed row" is unmet by the prototype, and a sync then deletes the skipped rows
Where: Behaviour 1 ("never skips a row: `parsers-refuse-ambiguity`"); AC2; Rules and mutants row 3 ("a parser that skips bad rows", `run`); prototype `provenance.luau:101-104` (`if string.sub(line, 1, 1) ~= "|" then continue`) and `:111` (`| (.-) | (.*) |$`); `provenance.spec.luau:132-142` (each bad row starts with `|`).
Evidence: probe (c) of the prototype's `parse` and `problems`:
- `| 2026-11-08 10:00 | ranked | human:Ann | rank=1 | extra |` (five cells): accepted, 0 audit problems.
- a row with no leading bar (`2026-11-08 11:00 | ranked | human:Eve | rank=9 |`, which GitHub's table syntax still renders as a row): accepted with the row skipped, 0 problems.
- a prose line between rows, an indented row, and a file with no blank line and no separator: each accepted, 0 problems.

Union probe: ours = base + the bar-less Eve row + a valid row, theirs = base + one row. `union` returns three rows and `Eve's rank=2 row kept: false`; `mergeRef` would commit that. `appendOnly` compares parsed rows, so a published append may also insert any such line anywhere in the file.
Critique: round 005 fixed this by adding shapes to the bad list, and the line filter that skips the rest survived. Adding these five shapes the same way leaves the next shape open. The mechanism is the parser picking the lines it likes.
Consequences: a strict grammar refuses hand edits and reformatting that the current reader tolerates, so audit then names the line to fix. No record exists yet (Where the new file bites), so nothing on main migrates. The union and `appendOnly` inherit the strictness for free.
Recommendation: parse the file as its exact grammar:
- line 1 `# Provenance: <id>`, line 2 empty, line 3 the table header, line 4 the separator;
- every further line a row of exactly four cells, the detail `[^|]*`;
- one final newline;
- anything else refuses, naming the line number.

Cases in provenance.spec: each probe shape above refused by `parse` and reported once by `problems`. Add a Rules row whose mutant is today's line filter.
Lesson: zz-arch/parsers-refuse-ambiguity, zz-test/refusals-tested-on-both-sides

### F3 [medium] `mergeRef`'s fail-safe ("a side that is not a valid record … aborts") has no case, and `union` never checks that each side extends the base: both paths lose rows silently
Where: Behaviour 5 ("on a conflict in any other file, or a side that is not a valid record, it aborts"); Interfaces (`union(base, ours, theirs): string`); prototype `main.luau:363`, `provenance.luau:223-225` (`(provenance.parse(ours)) or {}`) and `:238` (ours' new rows taken from index `#b + 1`).
Evidence: run (b) mutant M5, `if not ours or not theirs then` (the parse checks removed): survived. No case gives `mergeRef` an invalid side or a deleted one. Probes: with base [A, B], ours [A, B', C] (B edited, as `renumber`'s `rewriteUnder` edits an id in a detail) and theirs [A, B, D], the union is [A, B, D, C], so our edit is silently reverted. With ours [A, C] (B removed), the union is [A, B, D] and `our appended rafted row kept: false`. A branch carries no validator, so both shapes can reach the union, and `mergeRef` commits the result.
Critique: the tempting fix is one record.spec case for an unparsable side, which leaves the removal case losing rows.
Consequences: making `union` refuse changes its signature to `(string?, string?)`. A branch that edited an old row then sees its sync abort instead of a silent rewrite, so the abort must say what to do (name the row, and say how to restore it). `renumber`/`compact` edit old rows on a branch (`rewriteUnder`, `compact.luau:43`), so the design must say whether their rewrite counts as an edit, for example by comparing rows after mapping the ids, or by having `remap` and `renumber` run before rows exist.
Recommendation: put the fail-safe in the pure function. `union` returns nil and a reason when a side doesn't parse or doesn't extend the base (`appendOnly(base, side)` without the "one new row" clause), and `mergeRef` aborts on it. Add pure cases for the edit and the removal above, and a record.spec case: our side commits an unparsable `provenance.md`, main publishes a row, `./zn sync` fails naming the file, with no `MERGE_HEAD` and HEAD and status unchanged. Give each a Rules row, and decide the renumber/compact interaction in the Design.
Lesson: zz-test/pin-fail-safes-where-they-act

### F4 [medium] Not every merge of `origin/main` the engine makes, or tells the user to make, goes through `mergeRef`: `remap` merges with `merge-tree`, and six messages prescribe the plain `git merge` that zz-rules now forbids
Where: Behaviour 5 ("Every merge of `origin/main` the engine makes … goes through one function"); "Where the new file bites" ("`git merge` is not called anywhere else with `origin/main`"); the prototype's zz-rules Provenance ("never merge `origin/main` with plain `git merge`, which stops on the record").
Evidence: `git grep -nE 'git merge origin/main|merge origin/main' -- 'z-nile/engine/*.luau'` on c1e941f8 gives `main.luau:385` (mergeOrigin's failure: "resolve it with: git merge origin/main"), `:2357` (land), `:3106`, `:3230` and `:3236` (remap), and `:3440` ("If it has merged, git merge origin/main and retry"). `remap` merges at `:3233`, `git merge-tree --merge-base=<remapped base> HEAD origin/main`, then `commit-tree` and `merge --ff-only`. It has no `directoryRenames` and no union, so a record both sides appended fails remap with "git merge origin/main and resolve".
Critique: the one-function claim holds only for `git merge` calls. Following the engine's own advice hits a raw conflict in the record, or `CONFLICT (file location)` for a record in a moved folder. The tempting fix is rewording the messages alone, which leaves remap's merge outside the union.
Consequences: `remap`'s merge uses a synthetic base. Routing it through the union means reading the conflicted record's three stages from `merge-tree --write-tree`'s conflicted-file list (or merging the record afterwards with `mergeRef("origin/main")`), and the design must say which. The messages must give a path that works when the abort was for another file: resolve that file, then let the engine finish the record.
Recommendation: name `remap` in Behaviour 5 and unite its record conflicts, with a case (record.spec or a compact fixture) where both sides appended to one record across a compaction. Rewrite the six messages to send the user through `./zn sync`, and pin with one promoted case that the sync abort message no longer prescribes `git merge origin/main`.
Lesson: z-design/restated-rules-move-together, z-design/trace-every-way-code-runs

### F5 [medium] `merge.directoryRenames=true` changes every merge for every file, not only the record. A new file of any kind in a folder main moved now follows the move silently, and the design never says so or guards it
Where: Behaviour 5 ("the other files of the folder move by git's rename as before"); the prototype's zz-rules ("A record added in a folder `origin/main` moved (`ready`, `done`) follows the folder"); `main.luau:339`.
Evidence: git probe (c), run through `./zn run --time 60`. Base `t/rafts/active/R0010/{R0010.md,check.sh}`; main moves the folder to `t/rafts/R0010` (what `stop` does); our branch adds `review-001.md` there.
- Plain merge: `CONFLICT (file location): t/rafts/active/R0010/review-001.md added in HEAD inside a directory that was renamed in main, suggesting it should perhaps be moved to t/rafts/R0010/review-001.md`, with `AU t/rafts/R0010/review-001.md`.
- With `-c merge.directoryRenames=true`: `Path updated: … moving it to t/rafts/R0010/review-001.md. Merge made by the 'ort' strategy.`, exit 0.

So a raft worktree whose raft was stopped on main now syncs clean, carrying its review files into the backlog folder, where today the sync stops and names the move. The same holds for any branch adding files to an item that `renumber` or `compact` moved on main.
Critique: the flag is set per merge, not per path, so "only the record follows" can't be kept by rewording.
Consequences: (a) keep the flag, list each flow where a non-record file now follows (a stop under a running raft, renumber or compact of an item a branch adds to, done's promotion folder), and decide each one, for example by having `mergeRef` refuse when a path that followed isn't a `provenance.md`. (b) Merge without the flag and finish only the record's `CONFLICT (file location)` entries, which E14 shows already sit at the new path: take an `AU` `provenance.md` as ours and unite an `AA` one, aborting for any other path. (b) keeps today's behaviour for every other file and still passes record.spec's two folder-move cases.
Recommendation: choose (b), or (a) with each flow decided, and state the choice in Behaviour 5. Add a record.spec case where our side adds a non-record file (`review-001.md`) to a folder main moves, and `./zn sync` aborts as today, naming it. Add a Rules row whose mutant is "the flag moves every file".
Lesson: zz-arch/item-rules-scoped-to-their-call

### F6 [medium] The design never says which folders `./zn record` may write to for an active raft or a done item. The prototype accepts both, and no case pins either: the active raft is seeded and never recorded on, and no done item is seeded
Where: Behaviour 2 ("For an issue or a raft of the backlog, and for an issue in `active/`"); Overlaps ("c0250 (blocked; blocks whole rafts, hence a record in a raft's folder)"); c0250's Problem ("When any ticket of the raft blocks, **the raft is marked blocked**"); `record.spec.luau:99-106` (`rafts/active/R0150`, unused); `publish.spec.luau:74` (pins `publish.allowed` true for `issues/done/c0010/provenance.md`).
Evidence: in the prototype, `docPath` (`main.luau:321`) matches the document in any folder. The validator gives `done/` the full `PUBLISHED` list, and gives `rafts/active/` `{ "unblocked" }` only through the `/active/` substring (`publish.luau:462`). Run (b) mutant M4 (the active rule narrowed to `/issues/active/`, so an active raft takes `confirmed` and `ranked`): survived. `./zn record <done id> ranked` publishes into `done/`, which no sentence of the Design allows or refuses.
Critique: c0250, whose whole-raft block is the reason a raft has a record, will rely on whichever behaviour lands, and a wrong one passes.
Consequences: refusing `done/` is a new `cmd.record` refusal that needs its own message and case, and so is the validator's answer for a done path. Allowing it needs a reason in the Design. Either way the decided table must be spelled out once, in Behaviour 2 and Behaviour 3.
Recommendation: write the table in Behaviours 2 and 3:
- backlog issue or raft: `unblocked`, `confirmed`, `ranked`;
- active issue or raft: `unblocked`;
- done: refused before the publisher (or allowed, with why).

Cases: `./zn record R0150 unblocked` publishes in `rafts/active/R0150/`; `record R0150 confirmed` is refused with the tip unchanged; seed a done issue and assert the decided answer through `./zn record` and through publish.spec. Add Rules rows.
Lesson: zz-test/seed-every-enumerated-case

### F7 [medium] Three refusals and checks the Design states have no case: `record` in the main checkout, `record` offline, and audit of a malformed record anywhere but a backlog issue
Where: Behaviour 2 ("refuses … the main checkout", added by the lesson pass's `exhaustive-lists-name-new-things`); Edge cases ("Offline … `record` refuses as `spend` does"); AC5; `record.spec.luau:234-253` (every refusal is at `issues/c0050`).
Evidence: run (b) mutant M3 (`refuseInMainCheckout("record")` deleted, `main.luau:5091`) and mutant M2 (audit skips records under `/rafts/`): both survived. No promoted spec walks the usage text for main-checkout refusals: `grep -rln 'main checkout' z-nile/tests` gives per-command cases only (c0053/commands-*, c0070/board-refresh, c0116/plan-cli, c0119, c0120). Audit's raft case accepts a valid file, so a rule that skips rafts, `active/` or `done/` passes it.
Critique: these refusals pass by being absent. The main-checkout one guards the rule that the main checkout is only ever fast-forwarded.
Consequences: a main-checkout case must leave the main checkout's HEAD and origin's tip unchanged, and the fixture already has `f.main`. None otherwise.
Recommendation: record.spec cases:
- `./zn record c0011 confirmed` run in `f.main` is refused, with origin's tip and `f.main`'s HEAD unchanged;
- `PICKMAN_PUBLISH=0` is refused;
- `./zn audit` refuses a malformed record in `rafts/R0130/` and in `issues/active/c0090/` (and in `done/` if F6 lets done items hold records).

Add a Rules row for each.
Lesson: zz-test/guard-needs-its-own-case, zz-test/seed-every-enumerated-case

### F8 [low] The Overrides claim rests on a partial run, and the owed whole-suite run is placed after all the code (step 6) although the Regression guard says Phase 1
Where: Regression guard ("Owed: one `z-nile/check.sh --affected` … the executor's Phase 1 runs it"); Implementation steps 1 and 6.
Evidence: z-design's grep with each basename (`grep -rlF -e <name> z-nile/tests/acceptance z-nile/tests/tooling` for `main.luau`, `publish.luau`, `audit.luau`, `zz-rules`, `README.md`, `trail`, `provenance`) lists 61 files. Run (a) covered 17 of them that the design did not run (c0053/commands-sync, tooling/{ready-members,recombine-members,tracker-guarded}, c0114/{window,roots-cli,trail-move}, c0116/plan, c0069/prompt, c0115/{docs,readme}, c0184/docs, c0191/docs, c0239/docs, c0081/skill-doc, c0111/trail, c0120/trail-home): `118 passed, 0 failed`. No spec pins the rewritten direct-push sentence or the merge messages: a grep for the old clause "rows appended only (`./zn spend`), and" and for "resolve it with: git merge origin/main" finds nothing. Still unrun from that list: c0007/changed, c0042/page, c0043/format, c0050/start-depends, c0057/open, c0084/{commit-phase,ledger}, c0107/keep, c0114/{finished,gate-cover,layout,registry}, c0115/{freeze,layout,prompt}, c0117/dispatch, c0165/select, c0184/skills, c0191/{boundcmd,engine-cpu}, c0239/{done,land}, tooling/bounded-review. Since `main.luau` makes the selection `ALL`, so is every CLI spec outside the grep.
Critique: the claim is likely right, but an override found at step 6 stops a raft after all its code is written.
Consequences: none.
Recommendation: make the whole-suite run Implementation step 1 (apply the prototype's patch, run `z-nile/check.sh --affected`, escalate on any promoted red other than the named c0117/dispatch-cli), and cite run (a) in E16.
Lesson: z-design/confirm-overrides-with-a-suite-run

### F9 [low] The prototype every layer builds on is named by a local branch, not pinned, and the scripts behind E14 and E15 are not kept
Where: Implementation step 1 ("the shape is `proto-c0263-raft`'s"); Overlaps ("each prototypes on `proto-c0263-raft`'s shape"); E14 and E15; `experiments/` (only `split/`).
Evidence: `git ls-remote --heads origin 'proto-c0263*'` returns nothing (origin has `prep-ticket-provenance` only). No sha is recorded, and the branch's head is c1e941f8. The E14 scratch-repository script and E15's mutation script are not in `experiments/`, and the document doesn't say they ran through `./zn run`, so no `run` row can be replayed by id.
Recommendation: record c1e941f8 in E15. Commit the prototype's diff (`git diff 0ea4a484 c1e941f8 -- z-nile/engine z-nile/README.md z-nile/skills`) as `experiments/proto.patch`, and the E14 and mutation scripts, the latter keyed by Rules-row id. Say that each ran through `./zn run --time`.
Lesson: z-design/in-flight-bases-pin-their-source, z-design/mutant-ids-match-the-runner

### F10 [low] Stale labels, a vacuous docs needle and two assertions that can't fail
Where and Evidence:
- The headers carry the unsplit design's AC numbers: `publish.spec.luau:2` says "AC6" (it is AC4); `record.spec.luau:2` says "AC3, AC4, AC5" (AC3, AC5, AC6); `provenance.spec.luau:2` says "AC1, AC4, AC5" (AC1, AC2, AC5, AC7).
- `publish.spec.luau:3-5` says "a record in active/ … refused", but an `unblocked` row in active/ is accepted at `:138-145`. `:106` says "a stale approval made current by rewriting its design hash", while the edit changes `said="yes"` in a `confirmed` row.
- The docs needle `./zn sync` is already in zz-rules on main (`git show origin/main:z-nile/skills/zz-rules/SKILL.md | grep -cF './zn sync'` gives 3), so AC7's "the union through `./zn sync`" is pinned by nothing. `CLAUDECODE` stands alone for "the session variables".
- `provenance.spec.luau:215`, `union(nil, ours, theirs) ~= nil`, can't fail: `union` always returns a string.
- The folder-move case (`record.spec.luau:205-232`) says "(main's first)" but asserts only counts.

Recommendation: correct the labels and comments. Pin a phrase only the new text has, for example "never merge `origin/main` with plain `git merge`", plus `AI_AGENT`. Replace the nil assertion with the order of the rows (theirs first). Assert the order in the folder-move case.
Lesson: z-design/spec-design-correspondence, zz-test/no-vacuous-pass

Notes (not findings):
- Overrides: run (a) plus the 318 recorded cases make "none" plausible. F8 asks only to move the owed run.
- The publish broker and the git wrapper accept the new file: `trackerstate` is path-based, and `z-nile/bin/git` sends `-c … merge` through `wrap.luau` to the real git.
- `moveOnOrigin` carries every file of a folder, the record included.
- `rewriteUnder` and `compact` rewrite the record's header with the id, so audit stays consistent after a renumber (but see F3).
- `zn` runs the engine from the toplevel, so `mergeRef`'s repository-root paths are right.
- Repository safety: every spec writes only fixtures under `.cache` committing as `@example.invalid`; AC8 runs `./zn audit` and `./zn lessons --check` from `$ZN_ROOT` read-only, as c0116, c0117 and c0120 do.
- The re-prep added no lessons, so there are none to judge this round.

Candidate lesson (for the lead): a fail-safe that a pure function's caller enforces (a merge that "aborts when a side is invalid") belongs in the pure function's return, so a pure case pins it. Check: does any "refuses when X" in the Design live only in an adapter that no case reaches with X?

Verdict: changes
