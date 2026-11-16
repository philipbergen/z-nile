# Review 009: c0263 (design mode)
Inputs: prep `prep-ticket-provenance` at 137762c4: `c0263.md`, `check.sh`, `acceptance/{provenance,publish,record}.spec.luau`, `experiments/{proto.patch,mutants.py,folder-move.sh}`, `design-review-008.md`, `design-refute-008.md`, `harvest.md`. Prototype `proto-c0263-raft` at 507efe0e: its three spec copies are byte-identical to the sequestered ones, and `git diff 0ea4a484 507efe0e -- z-nile/engine z-nile/README.md z-nile/skills` is byte-identical to `experiments/proto.patch`. origin/main bb2a631a (f8cccd6c by the end; nothing touched changed in between). Reviews 003 to 007 were read for history only.
Dropped from review-008: F2, F3, F5, F6, F7, F8, F9, F10 (fixed; each fix read, and the strict parser checked by a mutant below). F1 is repeated only for the CLIs it asked to probe (F4 here), and F4's remap part is folded into F3.
Capture: `./zn capture c0263` prints `(no capture commit: first add)`, so it is not a confirmed capture. Judged from history: the Problem is unchanged since round 008's input (a4de4bc4), and round 008's scope reading stands.
Runs, all in a scratch clone of 507efe0e under the session scratchpad, with its `origin` pointed at a throwaway bare copy, every probe through `./zn run --time`:
- (a) A probe spec of three merge shapes, through `./zn sync` in a trackerfix fixture: `1 passed, 3 failed` (F1).
- (b) Plain-git probes in scratch repositories of the same shapes, and `git merge-tree --write-tree` on each (F1).
- (c) Four mutants on the pure module: reorder-blind `appendOnly`, reorder-blind `extends`, the multiset decrement dropped (F2, F5); "no final-newline check" (killed: `3 passed, 1 failed`).
- (d) Read-only probes of the installed `grok` and `agent` CLIs (F4), and `git apply --check` of `proto.patch` on bb2a631a (F6).

### F1 [high] `mergeRef` reads git's per-path stage shapes, and three reachable conflicts confined to the record abort with a false "deleted" message: our side moved the folder (`done`), or git's rename detection lost the record's pairing
Where: Behaviour 5 ("git leaves our added file at the new path with only our stage (E14), or with both stages … so `mergeRef` takes a path with our stage only as it is and unites one with both"); AC6 ("unite a conflict confined to `provenance.md`"); Usability ("a conflicting record is united by `./zn sync` with no hand work"); E14; prototype `main.luau:375` (`our side deleted the record`) and `:382` (`origin/main deleted the record`); record.spec's three folder cases (main moves the folder in all three, and none has a record in the base).
Evidence: run (a). Each case moves a folder with `git mv`, as record.spec does for main's moves:
- **UA.** Our side moves `issues/active/c0090` to `issues/done/c0090` (what `./zn done` does on a raft branch). Then `./zn record c0090 unblocked` publishes (an active issue takes it: Behaviour 2). Sync: `merging origin/main failed (merge aborted): pickman/.tracker/issues/done/c0090/provenance.md: our side deleted the record` / `CONFLICT (file location): …/active/c0090/provenance.md added in origin/main inside a directory that was renamed in HEAD`. `ls-files -u` shows stage 3 only.
- **DU.** The base holds c0021's record with one row. Our side moves the folder to `done/` and appends two rows (the delivered layers of c0282). Main publishes one `unblocked` row. Sync: `…/active/c0021/provenance.md: our side deleted the record` / `CONFLICT (modify/delete): … deleted in HEAD and modified in origin/main`.
- **UD.** The base holds c0019's record with one row, and our side appends one. Main publishes three `ranked` rows, then moves the folder to `active/` (ready). Sync: `…/issues/c0019/provenance.md: origin/main deleted the record` / `CONFLICT (modify/delete): … deleted in origin/main and modified in HEAD`.

Run (b) shows where the edge is. When main appends 1 or 2 rows before the move, git pairs the record and leaves `UU` at the new path, and the union works. With 3 or 5 rows, git calls it modify/delete. Git pairs a file by content similarity (50%), so an append-only file that more than doubles since the base loses its pairing.

In each case the only unmerged path is a `provenance.md`, so AC6 says unite. The prototype aborts instead, and its advice ("resolve what it names, then run ./zn sync") leads back into the same abort. `git merge-tree --write-tree ours main`, the test the dispatcher's merge gate makes (`dispatcher.luau:1536`), exits 1 on all three, so the PR stays unmergeable until a sync that can't succeed.
Critique: E14 and round 008 F5 already found that the folder move is a set of shapes that git chooses. The design handles the two shapes its cases produce (AU and AA, with main moving) and treats them as the whole set. Nobody listed the mirror case, where our branch moves the folder. `done` runs on the raft branch by design, and this layer itself opens published rows into `active/`, which `spend.md` refuses on purpose (`publish.luau:480`, "an active item's spend.md is recorded on its raft branch"). Nobody listed the similarity loss either. The tempting fix is two more branches (stage 3 alone: take theirs; stages 1+2 or 1+3: look for the other side's copy elsewhere). That would be the third patch on the same mechanism.
Consequences: reading the record by item identity instead of by path means:
- (a) one place per item: the record goes beside the item's document in the merged index, and every other record path of that id is removed;
- (b) the base is stage 1 when any unmerged path of the id has one, else none;
- (c) "deleted" can then only mean that the item's document is gone from the merged index, which is already a document conflict (abort, naming the document);
- (d) an id that changed (renumber, compact) is not the same item by id, so that case stays the stated limit and aborts;
- (e) a commit that holds two records of one id refuses.
Recommendation: question the mechanism. After a failed merge whose unmerged paths are all `provenance.md`, `mergeRef` should:
1. take each item id among those paths;
2. read that id's record from HEAD and from MERGE_HEAD, wherever each commit holds the id's folder (found by `<id>/<id>.md`);
3. take the base from stage 1 when present;
4. unite the sides, or take the one side that has the record (it must parse);
5. write the result beside the id's document in the merged index, `git rm` every other record path of the id, and commit.

It aborts when the document is unmerged or absent, or when one commit holds two records of the id. Give the lookup a pure helper over a `git ls-tree` listing (for example `provenance.locate(paths, id)`) with its own cases.

record.spec gets the three cases above:
- UA, through `./zn record` on an active item, with our side's `git mv` to `done/`;
- DU;
- UD, with three rows on main.

In each, `./zn sync` succeeds and leaves exactly one record, beside the document, with the rows in base, main, ours order, nothing at the old path, and an empty `status --porcelain`. Add Rules rows whose mutants are today's shape branches: stage 3 alone aborts; the old path is kept; theirs' new-path add is kept beside ours. Rewrite E14 and Behaviour 5's folder-move paragraph to state the rule.
Lesson: z-design/histories-checked-against-a-real-life (both sides of every move), zz-test/seed-every-enumerated-case

### F2 [high] A reorder passes every case: `appendOnly` and the union's `extends` can compare rows as a set, and nothing checks AC4's "refuses … a reorder" or AC2's "every old cell in place"
Where: AC2; AC4; Behaviour 3 ("every old row is unchanged in all four cells and in place"); Rules row "a record may only be appended to: every cell of every old row in place"; provenance.spec's append-only and union-refusal cases; publish.spec's refusals (origin's record holds one row at each of them, so no reorder can be built).
Evidence: run (c). The first mutant makes `appendOnly` check that each old row is somewhere in the new file, not at its own index: `provenance.spec` + `publish.spec` give `7 passed, 0 failed, 2 spec files`. The second makes `extends` (the union's base check) do the same: `provenance.spec` gives `4 passed, 0 failed`. Every append-only case either edits a cell (actor, detail, when) or drops a row; none swaps two rows.
Critique: a membership test is the natural first implementation of "the old rows are kept", so check.sh passes a validator that lets a published append reorder main's record. A reordered main then fails every branch's union ("origin/main's version changed or removed row N") and c0282's prefix gate. The tempting fix is one pure `appendOnly` case, which leaves the union and the publish path unchecked.
Consequences: none beyond the cases.
Recommendation:
- provenance.spec: `appendOnly(two, <two's rows swapped> .. <a new row>)` is refused, and so is `publishProblem`; `union` with either side's base rows swapped returns nil and a reason.
- publish.spec: after the valid append (origin then holds two rows), a publish that swaps them and appends a third is refused, naming the file.
- A Rules row for each mutant.
Lesson: zz-test/refusals-tested-on-both-sides, z-design/spec-design-correspondence

### F3 [medium] The new rule "never merge `origin/main` with plain `git merge`" and the rewritten abort text leave a genuine conflict with no working path, and five places still prescribe the plain merge
Where: the prototype's zz-rules Provenance (`SKILL.md:124`); `mergeOrigin`'s and `land`'s new texts (`main.luau:406`, `:2380`: "resolve what it names, then run ./zn sync"); record.spec `:295` (`has(…, "git merge origin/main")` must be false); AC7; Behaviour 5's "Limits, stated"; Open points ("none").
Evidence: `mergeRef` aborts on every conflict outside the record (Behaviour 5). After a sync names `c0050.md` (record.spec's own case), nothing is left in progress to resolve, and the next `./zn sync` aborts the same way. The only way through a document or code conflict is a merge by hand, which the new sentence forbids. On 507efe0e, `grep -nE 'plain .?git|merge it into the branch|resolve it like any merge|accept it \(`git add|merge `origin/main` and retry|git merge origin/main' z-nile/skills/zz-rules/SKILL.md z-nile/skills/zz-execute/SKILL.md z-nile/engine/main.luau` finds these places (its other hits, zz-rules:8 and :103 and zz-execute:52, are about `git add`/`git commit` and are left out):
- zz-rules:22, Conflicts: "A content conflict on a document … resolve it like any merge", and for `CONFLICT (file location)`, "accept it (`git add` that path)". Both need a merge in progress.
- zz-rules:78, the `start` row: "if `start` refuses, merge `origin/main` and retry" (the engine's own text now says `./zn sync`).
- zz-rules:113, Merging step 4: "merge `origin/main` in with plain `git`".
- zz-execute:101, Phase 5 step 2: "`git fetch origin main` and merge it into the branch now".
- main.luau:3129, :3253, :3259 (remap): "git merge origin/main and resolve (by hand)". These are kept, while zz-rules says "resolve that one by hand" two sentences after "never".

`mergeOrigin`'s text also still opens with "published, but" when `./zn sync`, which published nothing, is the caller.
Critique: the round-1 answer replaced a working instruction ("resolve it with: git merge origin/main") with one that loops, and record.spec now pins the loop. An agent that obeys zz-rules stops at the first ordinary conflict. The refute's remap answer ("Say so to the user") isn't recorded anywhere: Open points says "none".
Consequences: scoping the rule keeps the plain merge for genuine conflicts, so the hand procedure for a record caught in that merge must be written down (the union's order). Remap's stop needs the same procedure.
Recommendation: write one rule, once, in zz-rules Provenance, and point the rest to it: "merge `origin/main` with `./zn sync` (and the commands that merge for you), which unites the record. When it stops on another file, merge by hand with `git merge origin/main`, resolve every conflict, take a conflicted `provenance.md` as the common rows, then origin/main's new rows, then yours (no row twice), and commit."
- The abort text gives that path, without "published, but" when sync is the caller.
- record.spec `:295` pins the hand path instead of its absence (for example "git merge origin/main" together with "origin/main's new rows").
- Update zz-rules:22, :78 (`./zn sync`) and :113 (`./zn sync`, which needs no active raft), zz-execute Phase 5 step 2 (`./zn sync`), and the AC7 needle.
- Remap: escalate to the user, listing it under Open points until it is decided:
  - (a) unite records in remap too: `git merge-tree` already prints the conflicted-file info with each stage's blob, and `publish.luau` already builds trees with mktree. That is about 30 lines and one case.
  - (b) keep the stated limit, with a `Decided with the user` line.
Lesson: z-design/restated-rules-move-together, z-design/instructions-runnable-where-they-run

### F4 [medium] (repeat of design-review-008 F1, its probe of the other CLIs) The agent-session hint misses the `agent` CLI, which marks its shells `CURSOR_AGENT=1`, and grok sets none of the three variables. E5's "could not be probed here" is wrong, and in an interactive session of either CLI a record made without `--actor` names the user
Where: Behaviour 2 (E5: "the `grok` and `agent` CLIs of `.models.toml` could not be probed here"); `provenance.hint`; Usability ("never the user as a bot's work"); Q5 ("an interactive session without `--actor` records `agent:unknown` plus the effort"); AC1; record.spec's `HUMAN` table.
Evidence: run (d). Both CLIs are installed: `~/.local/bin/grok` is grok 1.0.70, and `~/.local/bin/agent` is cursor-agent 2026.10.22-27dcf5f.
- cursor-agent's `index.js` starts its shell tool with `{...process.env,...ol,CURSOR_AGENT:"1"}` and its terminal executor with `env:{CURSOR_AGENT:"1"}`. Its install holds no `AI_AGENT` and no `CLAUDECODE`.
- The grok binary's strings hold no `AI_AGENT` and no `CLAUDECODE`. Its `GROK_AGENT` is the agent-definition setting ("If the named agent is missing, Grok uses `GROK_AGENT`"), and its shell snapshot filters out `GROK_SANDBOX|GROK_AGENT=`. The binary doesn't show what its tool shells carry.

So `./zn record c0011 confirmed`, typed by an agent in an interactive `agent` or `grok` session, resolves to `human:<git name>`. Only dispatched steps are covered, through `ZN_DISPATCH`.
Critique: the hint is a list of known markers with the user's name as the default. Every CLI missing from the list is a silent mis-attribution, the one error the record exists to prevent. c0283's refusal of approve calls the same function ("Refuse in any agent session"), so it inherits the gap.
Consequences: every spec that asserts the human default must clear each added variable: record.spec's `HUMAN`, and c0283's specs.
Recommendation:
- Add `CURSOR_AGENT` to `hint`, with a provenance.spec case; a record.spec source case (`CURSOR_AGENT=1` gives `agent:unknown effort unknown`); `CURSOR_AGENT = ""` in `HUMAN`; and the variable in the zz-rules list and the AC7 needle.
- Probe grok's tool shell once (`./zn run --time 120 -- grok -p '<run env and print the variable names>'`) and add its marker. Record both probes as E5.
- If grok sets no marker, escalate to the user:
  - (a) a session that nothing marks records `unknown`, not the git name, when no `--actor` or `ZN_ACTOR` is given (a human sets `ZN_ACTOR` once in their shell profile);
  - (b) accept that an interactive grok session records the git user, amending Q5 with a `Decided with the user` line.
Lesson: z-design/live-defaults-checked-in-their-session, z-design/probe-free-cli-lines-in-prep

### F5 [medium] No case pins the union's multiset (Edge cases: "Two rows identical … are both kept"), so a union that drops a repeated row of ours passes
Where: Interfaces (`union`: "minus theirs' (a multiset)"); Edge cases; Rules row "a shared row once"; provenance.spec's union cases.
Evidence: run (c). The mutant removes `taken[k] -= 1` (`provenance.luau:289`), so ours' new rows are matched against theirs as a set: provenance.spec gives `4 passed, 0 failed`. A Lune probe through `./zn run --time 60` used base = one row, ours = base plus X plus X, theirs = base plus X. The prototype's union holds 3 rows and the mutant's 2. In every union case, ours' new rows differ from each other.
Critique: the mutant loses a row silently, which is the outcome the union's refusals exist to prevent.
Consequences: none.
Recommendation: two provenance.spec cases: ours appends X twice and theirs once, giving X twice (theirs', then ours' second); theirs twice and ours once, giving X twice. Add a Rules row whose mutant drops the decrement.
Lesson: z-design/spec-design-correspondence

### F6 [low] Records and texts that are wrong or stale
Where and Evidence:
- **Rules table vs mutants.py.** Row 5 lists "no final-newline check" and row 12 lists "our-only record dropped", and mutants.py has neither. The first is killed (run (c)); the second was never run. The table's wording also differs from the runner's names ("env wins over the flag" vs `env beats flag`, "the session hint ignored" vs `agent hint ignored`), so `mutants.py <name>` can't be run from a row.
- **Case count.** Affected specs says `record.spec.luau (9)`; E15 and the file say 11.
- **AC1's check.** check.sh's AC1 runs only provenance.spec, though AC1's "`./zn record` records the actor from each source" is in record.spec (the Test plan maps both).
- **zz-rules event list.** The Provenance paragraph says "The events are `approved`, `unblocked`, `confirmed`, `ranked`, `rafted` and `delivered`; `./zn record …` publishes the first three". The first three of that list are approved, unblocked and confirmed. The paragraph's last sentence then repeats the events table.
- **Implementation step 1.** `git apply --check experiments/proto.patch` on bb2a631a fails (`patch failed: z-nile/README.md:114`): R0083 rewrote the board bullet that is the hunk's context. `--3way` applies. Overlaps still treats R0083 as in flight.
- **Renumber limit.** Behaviour 5 calls renumber and compact "a rare, announced, whole-tree operation". Renumber is the routine fix for an id collision (zz-rules Conflicts) and rewrites every reference in every root (`rewriteUnder` over `store.roots()`). The union's message tells a renumbered branch to "restore it", which would undo the renumber. And a record that a branch added in a folder main renumbered merges cleanly (AU) with a header naming the old id, which audit then refuses. Neither matches the Edge case's "a sync after one stops with the union's message".
- **Empty file.** Edge cases says "Empty or missing `provenance.md`: no rows", but `parse` refuses an empty file (line 1), and no case says which behaviour is meant.
Recommendation:
- Fix each text.
- Give mutants.py one entry per Rules row, with the row's id as its prefix, and add the two missing mutants.
- Run AC1's check on both specs.
- Say `git apply --3way` in step 1, or rebase the patch onto today's main.
- State the renumber limit as what actually happens, and what to do instead of "restore it".
- Decide the empty file (refused, I'd expect) and add its case.
Lesson: z-design/mutant-ids-match-the-runner, z-design/restated-rules-move-together

Notes (not findings):
- Round-1 fixes checked by reading, and by run (c) where noted:
  - the parser reads exactly the grammar (the final-newline mutant is killed);
  - `hint` is pure and pinned per variable;
  - the union refuses an edited, removed or unparsable side, both pure and through `./zn sync`;
  - the done/active table is enforced in the command and in the validator;
  - the main-checkout and offline refusals have cases;
  - each AC7 needle is new: none is on origin/main's zz-rules, and README has no "provenance".
- Overrides "none": plausible. The 318 and 118 cases ran on the first prototype. The final one's changes (the flag removed, the strict parser, the union's refusal, three texts) reach only record conflicts and those texts, and the only promoted pin on them is `tooling/remap-once` (kept and rerun). Step 1's whole-suite run is still owed. Main moved since the prototype's base (R0083's `main.luau`, README and zz-rules; c0118's promoted specs), so that run must be on the patch applied to today's main.
- Merge edge cases that hold:
  - both sides deleting a record is no conflict;
  - a binary or NUL-bearing side fails `parse` and aborts;
  - two conflicted records in one merge are each united;
  - a rename/rename of a folder conflicts on the document and aborts.
- The publish broker (trackerstate, path-based; `itemOf` includes `retired/`), the board's history (`classify` takes only `<id>*.md`) and audit's `no-document` check for an orphaned record folder are unaffected.
- Repository safety: specs write only `.cache` fixtures, committing as `@example.invalid`. `mutants.py` edits files in a detached worktree and restores them; it moves no ref.
- No lesson was added or changed since round 008 (harvest.md maps round 008's findings onto existing lessons).

Candidate lessons (for the lead):
- A merge rule keyed on git's per-path stage shapes inherits git's rename heuristics. A small append-only file loses its pairing once it more than doubles, and each side's move gives a mirror shape. Check: does the rule find the record by its item (the document's place in each commit), and do the cases move the folder on each side, with a base record that grows past half?
- When a fix replaces an instruction ("resolve it with X"), run the new instruction on the failure it answers. Check: after the abort, can the user do what the text says, and does the next command then succeed?

Verdict: changes
