# Review 003: R0042 (design mode)
Inputs: branch `prep-z-nile` at 59ed0a9 plus the uncommitted prep tree: `tracker/rafts/R0042/{R0042.md,check.sh,design-review-00{1,2}.md,design-refute-00{1,2}.md,acceptance/tab.spec.luau}`, `tracker/issues/c0114..c0118/{<id>.md,check.sh,acceptance/*}`, `tracker/issues/c0115/experiments/namecopy.luau`, `tracker/issues/c0117/experiments/rank.luau`, and the uncommitted edit to `.claude/skills/tracker/SKILL.md`. Compared with `scripts/tracker/{main,status}.luau` (`cmd.new` raft branch, `setStatus`, `cmd.ready`, `carriedByPr`, `ALLOWED`), `tests/lib/trackerfix.luau`, `tests/acceptance/c0053/commands-prep.spec.luau`, and the architecture, testing, tracker, ticket-prep and review skills. I ran `selene` and `stylua --check` on the six prep folders (0 errors, exit 0), `namecopy.luau` (`pass`), `lune run scripts/affected -- .claude/skills/tracker/SKILL.md` (prints nothing), and the promoted specs c0043/format, c0107/keep, c0064/docs, c0081/skill-doc and c0052/skill-doc on this tree (all green).
Dropped from review-002: F1, F3, F7, F8, F11, F12. Their refutations fix what each finding named; I checked F1 (block split, experiment passes), F3 (lint clean) and F12 (each item is in the spec or the design). F2, F4 and F5 were fixed as stated, but each fix opens a new hole in the same mechanism, which is the third round for each one. Those are F4, F1 and F2 below, and their Recommendations question the mechanism. F6 is repeated as F5, F9 as F9, and the unlisted-project part of F10 as F8.

### F1 [high] c0116: the new `status <id> prepared` rule refuses z-raft's own step and today's ticket-prep, turns a promoted spec red with no Overrides line, and still cannot give an issue back
Where: c0116 Design, paragraph 4 ("`status <id> prepared` from `preparing` is allowed only when origin's document is `design: ready`"), paragraph 3 ("`z-raft` ... runs `status <raft> prepared`"); `scripts/tracker/main.luau:920-999` (`setStatus`); `scripts/tracker/status.luau:48-50` (`carriedByPr`); `tests/acceptance/c0053/commands-prep.spec.luau:84-114`; c0116 `Overrides: none`
Evidence:
- `new raft` publishes the raft from the template, so origin has `design: draft` (c0116 says so, and AC4 checks it). Publish accepts only `status:` edits to an existing document, so origin's `design:` stays `draft` until the prep PR lands. z-raft's `status <raft> prepared` is therefore always refused by the rule as written. The spec "prepared issues raft" never runs that command. It rewrites the stamps by hand and pushes to `main`, so it passes while the documented flow fails.
- The same rule breaks today's prep. `c0053/commands-prep.spec.luau:114` runs `trOk(cap, { "status", rz, "prepared" })` after setting `design: ready` only in the local files (lines 93-94, 110). Origin still says `draft`. Under c0116 that call fails and the promoted spec goes red. `main.luau` is Touched, so the Overrides line had to name it.
- The rule is also not needed for its stated purpose. `setStatus` already refuses a carried `prepared` move unless the local document is `design: ready` (main.luau:964-969). And `preparing → prepared` is always carried (`carriedByPr`): it only edits local files and publishes nothing (main.luau:982-984, 992-996). So "an abandoned z-raft gives a prepared issue back as `prepared`" cannot happen with this command. Origin keeps the `preparing-` stamp. The only published way back is `preparing → new`, which throws away a landed design.
- This is the third round with a hole in "who holds an issue while it is being rafted" (review-001 F7, review-002 F4).

Critique: The tempting fix is to read `design:` from the worktree instead of origin. That is today's rule, and it still leaves the give-back unpublished.
Consequences: A published give-back has to be a second kind of `preparing → prepared` move, picked per target. That is a new branch in `setStatus`, and it interacts with `stop`, the claim-stamp rule (R0025) and the raft-moves-its-members rule.
Recommendation: Stop patching sentences and write the hold mechanism as one table in c0116: origin state × command (`new raft`, `status preparing`, `status prepared`, `status new`, `recombine`, `ready`, abandon) → result and what gets published. Then pick one of these:
- (a) Per-target rule. `preparing → prepared` is published when origin's document is already `design: ready` (a landed design being given back). Otherwise it is carried, with today's local check unchanged, which keeps c0053 green.
- (b) Don't stamp prepared members at all. `new raft` claims only the raft (`preparing-…`). It refuses any member that an origin raft's `issues:` list already names. The carried `status <raft> prepared` accepts members that origin already shows as `prepared` and `design: ready`. Nothing then needs giving back.

I lean to (b): it adds no new published move. Either way, drop the origin-design sentence. Prototype the change as a scratch patch to `setStatus` and `cmd.new`, and run `c0053`, `c0067` and `c0068` plus `recombine.spec` against it. Add spec cases that run the actual `status <raft> prepared` from the worktree (no hand-edited stamps), and that abandon a z-raft and then show the member is `prepared` on origin (a) or was never restamped (b).

### F2 [high] c0116: recombine's "a `preparing-` stamp this command did not draw" has no ownership test, so it contradicts two of the spec's own cases and z-raft's main use
Where: c0116 Design, recombine paragraph; `recombine.spec.luau` "review files move" (205-217), "mixed types are refused" (66-77), "members move" (42-65); `main.luau:803` (`new raft` stamps the raft `preparing`)
Evidence:
- `new raft` always stamps the raft `preparing-<fresh>` (main.luau:803, 836, and c0116 for prepared members). In "review files move", both `keep` and `drop` come from `new raft`, so each carries a `preparing-` stamp that `recombine` did not draw. By the design's rule `recombine keep drop` must be refused, and the spec expects `r.ok == true`. No implementation can meet both.
- The design gives no way to tell "my" stamp from "a foreign" one. Claim files (`.cache/tracker-claim-<R-id>`, main.luau:305) exist only for `active`. After a merge, the worktree's copy of a foreign raft shows the same stamp as origin.
- z-raft's stated use is "folds ... into one open prepared ... raft". The raft being folded is fresh from `new raft`, so it is always `preparing-`, and recombine refuses it.
- In "mixed types", both rafts are also `preparing-`. If the implementation checks the stamp first, the error names the stamp and not `feature`, and AC2 fails unless the check order is fixed.
- AC1 says the moved member's status equals the keeper's. No case asserts any status. Also, "members move" seeds both rafts and both issues with the same `prepared-quiet-copper-falcon`, so even an added assertion could not fail.
- This is the third round on recombine's claim (review-001 F8, review-002 F5).

Critique: The tempting fix is a per-worktree stamp file written by `new raft` and read by `recombine`.
Consequences: That adds a third ownership store beside origin stamps and `active` claim files. It has to be cleaned up on `stop`, `status new` and worktree removal, and it is lost when a session moves to another worktree.
Recommendation: Question whether recombine needs to handle held rafts at all. Folding a prepared issue into an open prepared raft already works with today's commands: `status <keeper> preparing` claims the keeper and its members, `status <issue> preparing` claims the issue, the worktree adds it to `issues:` and `raft:`, and `status <keeper> prepared` carries the move. Write that flow into `z-raft`. Restrict `recombine` to two rafts that origin shows as `prepared-…` (no `preparing-` raft at all). It claims both with one fresh stamp and then edits the worktree. Rewrite "review files move" and "mixed types" to seed `prepared` rafts. In "members move", seed the two rafts with different `prepared-` stamps and assert that the moved member's worktree status equals the keeper's. Fix the check order (type, then project, then state) so each refusal names its own reason. Add a case: a `new raft` result (`preparing-`) given to `recombine` is refused and names `preparing`.

### F3 [high] c0116: three Checked clauses have no spec case, and the Rules table still describes the review-002 design
Where: c0116 AC1, AC4; Rules and mutants table rows 4-5; `recombine.spec.luau`
Evidence:
- AC4: "`new raft` of a pickman issue and a z-nile issue exits non-zero, names `project`, and publishes nothing." No case runs `new raft` over two projects. The only project case runs `recombine`. The mutant "`new raft` ignores `project:`" passes.
- AC4: "`status <id> prepared` is refused for a `design: draft` issue and names `design`." No case runs `status`.
- AC1's status clause is unchecked (F2).
- The Design says a mix of `new` and `prepared` members is refused. That rule has no row and no case.
- Row 4 reads "prepared members keep their status, the raft is `design: ready`", and its listed mutant is "restamp the members `preparing`, or leave the raft `design: draft`". That mutant is now the designed behaviour.
- The other new rules (cross-project `new raft`, the status/design rule, foreign-stamp refusal, check order) have no rows.

Critique: The tempting fix is to add the cases as written.
Consequences: The status/design case depends on how F1 is resolved, and the foreign-stamp case on F2. Adding them before that pins the contradiction.
Recommendation: After F1 and F2, rewrite the Rules table from the Design, one row per rule. Add cases for: `new raft` over a pickman and a z-nile prepared issue (origin tip unchanged, error names `project`); a `new` plus `prepared` mix refused (tip unchanged); and whichever status rule F1 settles on, run through the real command.

### F4 [high] c0117: every issue lists its own acceptance spec under Touched modules, so the root spec always joins `strongest`, and a closer file can never lower a cap
Where: c0117 Design ("the directories are only the directories of paths listed under `### Touched modules`"); the Touched modules of c0114-c0118 (each ends with `tracker/issues/<id>/acceptance/<spec>.luau`); `models.spec.luau` "dry run and model flag" (fixture lists only `game/x.luau`)
Evidence: A search for Touched-modules lines that start with `` - `tracker/issues/ `` and contain `acceptance` finds that line in all five R0042 issues and in about 50 other issues across `tracker/`. For an issue that touches `game/x.luau` and its own `tracker/issues/<id>/acceptance/a.spec.luau`, the directories are `game` (cap 1000) and `tracker/issues/<id>/acceptance` (root only, 300000). `strongest` picks 300000. The Problem ("give one directory a cheaper cap") never happens for an issue written to this repo's convention. AC7 passes only because its fixture leaves the spec path out. Issues of a nested game also stay under `tracker/` (c0114), so their specs always resolve to the root. Touched modules is prose that execution edits, and its spec paths change when the specs are promoted. This is the third round with a hole in the directory-to-spec rule (review-001 F11, review-002 F2).
Critique: The tempting fix is to skip paths under `tracker/`.
Consequences: After promotion the spec lives in `tests/acceptance/<id>/`, so `tests/` would need skipping too. Then a real test-only chore resolves to nothing and falls back to the root, which is fine but has to be stated.
Recommendation: Question deriving the model directory from free-text Touched modules. Either:
- (a) Resolve from an explicit key: a frontmatter `models_dir:` (default: the repo root), or a directory per project in `projects.toml`, which changes c0114.
- (b) Keep Touched modules, but state the filter: skip `tracker/` and `tests/acceptance/`, and an empty result means the repo root.

Either way, add to AC7's fixture an issue that touches `game/x.luau` and `tracker/issues/c0001/acceptance/a.spec.luau` and still prints `max_tokens=1000`. Run that case against a scratch `models.luau` prototype in prep; the merge rule is about 40 lines.

### F5 [high] (repeat of review-002 F6) c0118: the reader case passes a reader that ignores projects and done commits, and RC2 still never runs the reader
Where: `view.spec.luau` "reader" (132-203); `R0042/acceptance/tab.spec.luau:26-32`; R0042 Exit criteria RC2
Evidence:
- The case asserts only that `2026-W53`, `grok-4.7` and `c0001` appear anywhere in the HTML. All seeded files sit in one commit, amended to `2026-12-28T00:00:00Z`, and the spend row's `when` is `2026-12-28 00:00`. So each of these readers gives `2026-W53`: one that dates by HEAD, one that dates by the spend row, and one that dates every item by its last commit. The "commit that put a raft in `done/`" rule is not isolated.
- A reader that sets every item's project to `pickman`, or embeds raw spend rows, still prints `c0001` and `grok-4.7`. Review-002 F6 asked for "the z-nile id is only on the z-nile tab, the raft's reviews land in `2026-W53`, and the model's tokens are on its project". None of the three is asserted.
- RC2 still reads `project:` from the published document, copies it into a hand-built `Item`, and calls `view.build`. The refutation did not address RC2. So "a z-nile issue is only on that tab" through `tracker.sh view` is checked nowhere.

Critique: The tempting fix is more substring checks.
Consequences: The page embeds the view JSON in `<script type="application/json" id="z-nile-view">` (c0118 Design), so a spec can decode it with `serde` and assert structure, not text.
Recommendation:
- Seed the fixture at an older date (for example `2026-11-02T00:00:00Z`). Then move R0001 into `rafts/done/` in a second commit dated `2026-12-28T00:00:00Z`, and give the spend row a `when` in another week.
- Decode the embedded JSON. On the z-nile view, assert: card `c0001`, `weeks` = `2026-W53` with design 1 and development 1, and `tokens["grok-4.7"] == 12`. On the pickman view, assert: card `c0002`, no `c0001`, no weeks, no tokens.
- Make RC2 run `tracker.sh view --out … -O` on its fixture and decode the same JSON, instead of calling `view.build` on a hand-built table.

### F6 [medium] The prep tree edits the live `.claude/skills/tracker/SKILL.md` now, pointing at a file no branch has, and c0116 both disowns and requires that edit
Where: uncommitted diff to `.claude/skills/tracker/SKILL.md:63` ("**Current raft rule.** Creating and recombining rafts follows `.claude/skills/zz-rules/SKILL.md` (`z-raft`)..."); c0116 Non-goals ("Editing ... `.claude/skills/tracker/SKILL.md`"); c0116 Design ("gains one line"); c0116 AC3; Touched modules
Evidence:
- This line rides in the prep PR, so it lands on `main` before R0042 starts. From then on, every readied prompt (the tracker skill is in `SKILLS_INLINED`) tells executors that the ticket-prep sentences are "the pinned old path" and points them at `zz-rules` and `z-raft`, which don't exist until c0115 and c0116 land. If R0042 is stopped, the pointer stays on `main` indefinitely.
- c0116 lists that file as a non-goal and leaves it out of Touched modules, yet its Design and AC3 require the line. Because prep already wrote it, AC3's clause passes before any work is done.
- c0115 then copies `tracker` into `zz-rules`, so `zz-rules` will contain a line telling the reader to follow `zz-rules`, and calling its own ticket-prep sentences obsolete.

Critique: The tempting fix is to leave it, since the line is harmless text.
Consequences: Reverting means c0116 owns the edit. That puts `.claude/skills/tracker/SKILL.md` in Touched modules, and `affected` prints nothing for that path, so only the full gate guards it.
Recommendation: Revert the edit in the prep tree. Move it from c0116's Non-goals into its Design and Touched modules, as an execution step. Have c0116 drop that line from `zz-rules` (or never copy it) so `zz-rules` states the rule directly.

### F7 [medium] c0117: `dispatch` for a raft is specified but never checked, though `z-run` acts on a raft
Where: c0117 Scalability ("A raft step resolves every member and calls `strongest` once"); AC7; `models.spec.luau` "dry run and model flag"
Evidence: AC7 runs `dispatch z-run c0001` and `c0002`, both issue ids. `z-run` is the merged launch-raft and execute-raft, and its argument is an R-id. Nothing says what `dispatch z-run R0001 --dry-run` resolves. The fixture's R0001 lists only `c0001`, while `c0002` also names `raft: R0001`, so the set is ambiguous (the `issues:` list, the `raft:` fields, or the claim stamp). Mutants that pass: "an R-id resolves the repo root only" and "an R-id is an error".
Critique: The tempting fix is a case with an R-id and no stated rule.
Consequences: The member set must be one of the three, and it must match what `ready` and `stop` use (stop uses the claim stamp, main.luau:2807-2811).
Recommendation: State that a raft resolves the issues on its `issues:` list (the set `ready` checks) and takes `strongest` over all their directories. Fix the fixture so R0001 lists both issues. Add a case: `dispatch z-run R0001 --dry-run` prints `max_tokens=300000`, and the same command for a raft whose only member touches `game/` prints `max_tokens=1000`.

### F8 [medium] (repeat of review-002 F10, unlisted-project part) Rules the refutations added have no case: the `unknown` view and the emergent issue's project
Where: c0118 Design ("one extra view whose id is `unknown`"); c0114 Design ("An emergent issue with `--raft` and no `--project` copies the raft's project ... `--project` with a different id is refused"); both Rules tables
Evidence: `view.spec` has no item whose project is outside `projects`. The mutant "drop it" (the behaviour review-002 F10 warned about) passes. `home.spec` has no `new issue --raft` case, so the mutants "write `pickman`" and "accept any `--project`" pass. Neither rule has a row.
Critique: The tempting fix is the `unknown` case only.
Consequences: The `unknown` view sits after the listed ids, and `render` gives it a tab. AC5's "no tab for `gamma`" must still hold when `gamma` is not given at all.
Recommendation: Add a row and a case to each. `build` with `projects = {"alpha"}` and one item with project `gamma` gives views `alpha` and `unknown`, with the card on `unknown`. In a fixture with an active z-nile raft (seeded, with `project: z-nile` on its member), `new issue c x --raft R0001` writes `project: z-nile`, and `--project pickman` with `--raft R0001` exits non-zero and publishes nothing.

### F9 [medium] (repeat of review-002 F9) Every row is still `reasoned`, only c0115 records why, and the reason given would excuse every design
Where: Unknowns & experiments of c0114, c0116, c0117 and c0118 (no reason recorded); c0115 E1 ("the skill files do not exist yet, so a mutant cannot be applied")
Evidence: The ticket-prep skill (line 59) requires a reason in Unknowns & experiments for every `reasoned` row. Four of the five issues give none. The reason c0115 gives ("does not exist yet") is true of every new module, so it would make `run` optional for every design. New evidence that running is cheap and would have caught this round's defects:
- F1 needs no new module. A three-line scratch patch to `setStatus`, run with the promoted `c0053/commands-prep.spec`, fails at line 114.
- F2 is visible by reading `cmd.new` (main.luau:803) beside the "review files move" case.
- F4 needed one look at any issue's Touched modules.

Critique: The tempting fix is to write "modules don't exist" on each issue.
Consequences: Prototypes cost prep time, but each round of reading-only fixes has produced a new high finding in the same mechanism.
Recommendation: For c0116, mutation-run the `new raft` and `status` rows against a scratch patch of `main.luau`, together with c0053, c0067 and c0068. For c0117, run the `resolve`/`strongest` rows against a scratch `models.luau`. Record the outcomes. For any row that stays `reasoned`, write a reason specific to that row.

### F10 [low] Smaller gaps
Where: c0114 Design (`list --project`); c0115 frontmatter; R0042 Risks
Evidence:
- c0114 says `list --project z-nile` "prints only issues". Review-002 F7 asked that rafts follow the derived project, and nothing says whether a z-nile raft is listed.
- c0115 has `depends_on: [c0114]` but reads nothing c0114 adds.
- R0042 Risks says the tenth cell "appears only on a row that has a model". c0117 renders ten cells for every row once any row has a model.

Critique: Each is a question an executor would ask.
Consequences: none
Recommendation: State whether `list --project` includes rafts by their members' project. Either give c0115 a reason for the dependency or drop it, and keep the R0042 order. Reword the Risk to "a file that has at least one model row renders ten columns".

Verdict: changes
