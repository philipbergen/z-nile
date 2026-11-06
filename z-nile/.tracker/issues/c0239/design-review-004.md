# Review 004: c0239 (design mode)
Inputs: HEAD e790ae40 plus the uncommitted prep tree. I copied and shasummed it at the start, and it was the same at the end (`shasum` of the folder 235a841b…): `z-nile/.tracker/issues/c0239/{c0239.md,check.sh,acceptance/{docs,done,land,stop}.spec.luau,acceptance/{narrow,rehash}.py,design-review-00{1,2,3}.md,design-refute-00{1,2,3}.md,harvest.md}`, plus the lessons the prep adds or edits. I also read `./zn capture c0239`. It holds only "split from c0165", so scope is judged against the Problem's quoted capture and its Scope/Decided lines. Other inputs: c0165's code and `gatefix.luau` on `origin/R0081-reuse-test-results` (ecc0adaf); `scripts/hooks/stop.sh`; `z-nile/engine/{gate,main}.luau`; the skills, templates and `SETUP.md`; every promoted spec; every in-flight item's `check.sh` and `acceptance/`.
Dropped from design-review-003: F1 (narrow.py now substitutes all four `toBe("full")` and asserts the count; run below). F2 (the stub and the declarations are in the base commit; run below). F3 (no real file is overwritten, and the hook cases pass on a prototype; the unrun-prototype half is part of F2 below). F4 (zz-execute Phase 6 step 1 is pinned; the command it names is F3 below). F5 (CI is no longer named as a gate). F6 (the inputs.tsv lines are pinned). F7 (items 1 to 9 are answered; leftovers are in F6 below).
The user's decisions of 2026-11-04 ("A: done affected, merge full"; "ship it, state the limit"; "BLOCKED and stop") are respected and are not findings. Every captured outcome (the Problem's bullets, its Scope and Decided lines, and the Solution's restatement list) has a Design and a Checked criterion.

**Prototype (this round's evidence).** It is a scratch repository outside the repo (`git init` plus a fetch of `origin/main` bdcaea23 and `origin/R0081-reuse-test-results` ecc0adaf). R0081 is merged with main (fc211f7a). c0165's `acceptance/` is promoted by hand to `z-nile/tests/acceptance/c0165/` (1c3e8626) and set as the simulated `origin/main`. Then come this prep's issue folder (0d4afbba) and a prototype of the Design (48b48cf4, 27f8272f):
- `doneGate` returns `"affected"`, and the done branch has the new command and messages;
- the five Overrides, made by narrow.py's own SUBS, then `stylua --check` (clean), then `rehash.py`;
- `select.scope(ctx, changed)` (rules 1 to 4) and a `specs.luau scope` command (prints `ALL` on any failure, exit 0);
- `stop.sh` runs `--affected --project <name>` only for a `[A-Za-z0-9_-]+` answer other than `ALL` with exit 0;
- the template's RC0 is `--affected`.

Every run went through `./zn run --time …`. Results:
- `stop.spec` passes 6/6 in about 8 s. `done.spec`, the narrowed `c0074/done-gate.spec` and `land.spec` pass 9/9. `narrow.py` passes. `./zn promote-check c0239` passes there: E3 is confirmed, and both TypeErrors go away once `gatefix` resolves. `./zn check c0239` gives 5/8: AC4 to AC8 pass, and AC1 to AC3 fail only because I did not write the wording.
- Mutants killed:
  - `scope` with an uncommitted-only change set: stop.spec:115.
  - `scope` always `ALL`: :115 and :157.
  - rule 2 dropped: :107.
  - rule 1 dropped: :115.
  - rule 3 dropped, taking the first project: :140 and :150.
  - the hook ignoring `scope`'s exit status: :173.
  - the hook trusting any output: :169.
  - `done` still streaming `--full`: done.spec and two c0074 cases.
  - the rollback dropped: c0074 "a failing gate rolls everything back".
  - `promoted` gone: two c0074 cases.
  - narrow.py with one `args: --affected` line deleted, or with another c0172 digest changed: red.
- Mutant that survives: rule 4 dropped (F2).
- The whole z-nile suite on the prototype gives 1454 passed and 2 failed. One failure is my setup: `c0116/retired`'s `lessons --check` can't find the prep's new lesson files, which I didn't copy. The other is real: F1.

### F1 [high] The template's RC0 change turns the promoted `c0120/homes.spec.luau` red, and it is in neither the Overrides, narrow.py nor AC8's allow-list
Where: Checklist "Overrides"; Regression guard `Overrides:`; check.sh AC8 `OVERRIDES`; `acceptance/narrow.py` SUBS; AC2.
Evidence: `z-nile/tests/acceptance/c0120/homes.spec.luau:460`, case "a raft made online gets its project's gate in RC0", creates a raft with `./zn new raft … --project z-nile` and asserts `has(check, '"$ZN_ROOT/z-nile/check.sh" --project z-nile --full')`. On the prototype with the template's RC0 at `--affected` (the text AC2 requires), the z-nile suite fails exactly there: `homes.spec:460: expected true, got false`. The search that finds it, with every hit pasted (`git grep -nE 'check\.sh"? --project [^ ]+ --full|project gate passes' -- '*/tests/**' '*/.tracker/**/acceptance/**' '*/.tracker/**/check.sh' | grep -v /done/ | grep -v issues/c0239/`, minus the raft `check.sh` files' own RC0 lines):
```
z-nile/tests/acceptance/c0114/docs.spec.luau:172     (named)
z-nile/tests/acceptance/c0120/docs.spec.luau:172     (named)
z-nile/tests/acceptance/c0120/homes.spec.luau:460    (NOT named)
z-nile/tests/acceptance/c0120/promote-home.spec.luau:130 (named)
```
The Overrides were found by searching for the template's literal text (`RC0: project gate passes (full)` … `{{PROJECT}} --full`). homes.spec pins the rendered form (`--project z-nile --full`), with no label and the project substituted, so that search missed it.
Critique: With the Design as written, z-nile's gate is red on every tree once AC2 holds. Editing homes.spec to fix it fails AC8, whose `promoted_unchanged` forbids any promoted change outside the five. So no implementation passes the gate and AC8 together, and both are sequestered. The tempting fix is to add homes.spec as a sixth entry. That repeats the list-from-memory mechanism a third time (rounds 2 and 3 found the same kind of gap in this list).
Consequences: homes.spec's case title stays true ("gets its project's gate in RC0"), so only the one string changes. Its file pins nothing else c0239 touches (the suite shows no other failure in it). c0178 (R0073, active), which also overrides `c0120/*` specs, does not touch homes.spec (`git grep -l homes.spec -- z-nile/.tracker/issues/active/c0178`: no hits).
Recommendation: Add `z-nile/tests/acceptance/c0120/homes.spec.luau` to the Checklist Overrides, the Regression guard line and AC8's `OVERRIDES` regex. Add a SUBS entry in narrow.py, `('"$ZN_ROOT/z-nile/check.sh" --project z-nile --full', '"$ZN_ROOT/z-nile/check.sh" --project z-nile --affected')`, with its count asserted (1). Paste in the Design the search above that derives the Overrides list: rendered forms, both quote styles. Then rerun the whole z-nile suite on a prototype with the template changed, and record that run as the proof that the list is complete. A grep can't show completeness here, because the pin is assembled from parts.
Lesson: z-design/migration-search-matches-built-names

### F2 [high] No case kills `select.scope`'s rule (4): a `scope` without it passes all of stop.spec, and the Rules row's "path outside every home" is a path that forces (repeat of design-review-003 F3's method half: the Rules table is still unrun)
Where: Design, Stop hook (rule 4: "every changed path lies under that project's home or its tracker root … keeps the other projects' static stages … in the unscoped call"); stop.spec lines 119 to 129 and 160; Rules row "scope never narrows" ("a path outside every home … give `ALL`"); every Rules row `reasoned`; refute 003 F3 ("the prototype mutation check stays `reasoned` in this prep").
Evidence: on the prototype, the mutant that replaces rule 4's test with `if false then` gives `6 passed, 0 failed`. Every "outside the home" path in stop.spec forces a full run through rule (1): `scripts/other.sh` and `zn` match `SHARED_FULL` (`^scripts/`, `^zn$`, select.luau lines 25 to 35 on R0081), and `z-nile/lib/changed.luau` does too. So rule (4) is never the reason for an `ALL`. With cases added in a scratch copy (`extra.spec`, the same fixture and helpers), the correct prototype answers:
```
pickman/src/A.luau,SETUP.md -> true ALL
pickman/src/A.luau,z-nile/tests/notes.md -> true ALL
pickman/src/A.luau,z-nile/.tracker/notes.md -> true ALL
pickman/src/A.luau,pickman/.tracker/notes.md -> true pickman
```
and the rule-4 mutant fails the first one: `expected "ALL", got "pickman"`. The author wrote the spec and the Rules table without a prototype, although review 003 F3 asked for one and c0165's code was on R0081. That would have shown this in one run.
Critique: rule (4) is the Design's own guard for the other projects' format, lint, type and build stages. A hook that drops it runs `--project pickman` while a root doc, z-nile's tests folder or another project's tracker changed. This is the third round in a row to find an unkilled or vacuous stop.spec case. The tempting fix is to add one `SETUP.md` case and keep the rows `reasoned`.
Consequences: the cases need paths that neither force nor select. A root file (`SETUP.md`), a non-spec file under another home's `tests/` (`z-nile/tests/notes.md`: `forces` exempts `z-nile/tests/`) and another project's tracker root all qualify, and the fixture builds them without a new `make` (no new fixture build). The positive case (the project's own tracker root, `pickman/.tracker/notes.md` → `pickman`) pins the "or its tracker root" half.
Recommendation: add the four `expectScope` lines above to the "scope names a project" case, and `hook(dir, { "pickman/src/A.luau", "SETUP.md" })` → `--affected` to the AC7 case. Fix the Rules row: "a path outside the project's home that does not force (a root doc, another home's non-spec file, another project's root)". Then record, in Unknowns, a prototype run with the sha it was cut from (z-design/in-flight-bases-pin-their-source), with every Rules row's mutant run and marked `run`. The prototype described under Inputs is one way to do it.
Lesson: z-design/prove-specs-pass-on-a-prototype

### F3 [medium] The pinned BLOCKED sentence tells the merger to compare against `origin/main` in the clone where Merging step 2 has removed origin, so every failing spec is filed as a graph miss
Where: Design rule table, last row; docs.spec lines 115 to 118 (zz-execute Phase 6 step 1); zz-rules Merging step 2 (pinned by c0172/merge.spec: `git remote remove origin`).
Evidence: the merge's full gate runs "in a clone outside this repo", and its origin is removed. In such a clone of the prototype (`git clone --no-hardlinks`, then `git remote remove origin`), `git rev-parse -q --verify origin/main` fails (status 1), and `lune run z-nile/affected -- --base origin/main` exits 0 and prints nothing. `changed.files` gets no merge base and falls back to the empty working-tree diff. So "for each failing spec that `… --base origin/main` does not list" covers every failing spec. In the raft worktree the same command printed `ALL` (the PR touches forcing paths). The sentence doesn't say that `ALL` means every spec was selected, so read literally, every failing spec is again "not listed". A spec that fails on `main` itself (red main now first shows here, by the user's "No baseline") is not in the PR's selection either, and gets filed as a graph miss. Review 003 F4 suggested `--base <merge base of the done commit>` run at the done commit. The pinned text dropped both halves.
Critique: the user chose "BLOCKED and stop", and the graph-miss filing is the Design's addition so the user can tell a graph miss from a red `main`. As written, that addition files a wrong chore in every case it runs, and it sits permanently in a promoted docs pin.
Consequences: naming the place (the raft worktree, at the done commit) and the base (the merge base of that commit with the `origin/main` it merged) makes the command reproduce `done`'s selection. A failing spec that also fails on `origin/main`'s tip is red main, which is c0240's report, not a graph miss.
Recommendation: rewrite the sentence and its docs.spec pin along these lines: "… for each failing spec that `lune run z-nile/affected -- --base $(git merge-base <done commit> origin/main)`, run in the raft's worktree at the done commit, neither lists nor answers `ALL` for, file a graph-miss chore (zz-test, Graph miss) and say so in the comment; a spec that also fails on `origin/main` is red `main`, reported as such." Add a Rules row with its mutant (the sentence says `--base origin/main`, or names no place).
Lesson: z-design/instructions-runnable-where-they-run

### F4 [medium] Existing work misses c0083 (prepared, R0030), whose design and sequestered check.sh contradict this issue's decisions and Overrides
Where: Checklist "Existing work"; `z-nile/.tracker/issues/c0083/{c0083.md,check.sh}`.
Evidence: c0083's AC9 (check.sh lines 152 to 178) requires `land` to default to `--affected` (`override or "scripts/check.sh --affected"`, "land does not default to …"). That contradicts AC5 and the user's "merge full". It also requires c0074/done-gate.spec to "still say `full gate fails` and `full gate is skipped`, and still have at least four `toBe("full")`" (lines 175 to 178), and c0239's Override removes all three. c0083.md line 30 makes "Renaming `gate.doneGate`'s return value `"full"`" a non-goal, and line 128 rewrites the zz-rules `done` row differently. Search: `git grep -lF -e 'toBe("full")' -e 'full gate fails' HEAD -- '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**' | grep -v /done/` → `z-nile/.tracker/issues/c0083/check.sh`. Also `z-nile/.tracker/issues/c0112/acceptance/docs.spec.luau`, which pins an unrelated "The full gate fails when `--check` …" sentence that c0239 does not touch. c0165 already says c0083 "must be re-prepped" for old paths, and no capture exists (`git grep -l c0083 -- '*/.tracker/issues/*/*.md' | grep -v /done/` lists only c0161, c0165 and c0173 discussion).
Critique: R0030 can be readied as it stands. Its sequestered AC9 could then never pass after c0239, and its design would reverse the user's "merge full" if anyone followed it. z-design/new-rules-migrate-existing-work asks the design to say what each such item does.
Consequences: c0239 can't edit c0083's sequestered files, and the fix to c0083 is a re-prep. Whether c0083's "land and Merging affected" survives at all is the user's decision, against the 2026-11-04 "A".
Recommendation: name c0083 in Existing work, with the three contradictions above. Capture a re-prep issue (`./zn new issue c c0083-reprep-after-c0239 --project z-nile --desc …`) that says c0239's narrowing invalidates c0083's AC9, and that the user's "merge full" decision governs land and Merging. Add the issue to the Design as a handoff, as c0241 is for c0180.
Lesson: z-design/new-rules-migrate-existing-work

### F5 [medium] done.spec and land.spec pin text in `z-nile/engine/main.luau`, which c0180 (after this issue, via c0241) splits into `engine/cmd/<name>.luau`, and nobody who re-preps c0180 is told
Where: `acceptance/done.spec.luau` line 11 and `acceptance/land.spec.luau` line 11 (`fs.readFile(`{root}/z-nile/engine/main.luau`)`); the inputs.tsv lines for them; Checklist "Existing work" (it names c0241 only for its requote).
Evidence: c0180.md line 57: "each of the 37 commands moves … to `z-nile/engine/cmd/<name>.luau`". c0180's `acceptance/narrowings.luau` line 21 already rewrites c0074's `main.luau` read for this reason ("done moved to engine/cmd/done.luau"). c0239's two new promoted specs make the same move break two more files, and c0241's text names no c0239 spec (`grep -n 'done.spec\|land.spec' c0241.md`: no hits). On the prototype, the `done` mutant that still streams `--full` is killed by the overridden c0074 too, so done.spec's text pin adds no kill c0074 lacks. Its messages pin is the only extra.
Critique: a promoted pin on a file's location, which a known follow-up removes, will turn red when c0180 lands, unless c0180's re-prep happens to find it (z-design/pins-name-who-reprep-goes-first).
Consequences: reading the strings from every file under `z-nile/engine/` survives the split, but then the declared input becomes the folder `z-nile/engine/` (which forces z-nile anyway).
Recommendation: make done.spec and land.spec search `z-nile/engine/**/*.luau` for their strings, so the split keeps them green. Or keep them as they are, and name both in Existing work and in a note on c0241 (a capture line in its document) as Overrides c0180 must carry. State which one in the Design.
Lesson: z-design/pins-name-who-reprep-goes-first

### F6 [low] Leftovers
Where: `z-nile/templates/prompt.md` line 9; zz-rules `done` row; stop.spec line 122; check.sh AC8; the Problem's Solution bullet.
Evidence:
(1) prompt.md line 9 says the raft's `check.sh` "covers the full repo gate plus every issue's `check.sh`". Once RC0 is `--affected`, that is false. It is in neither the Wording list nor an `unsays` (`git grep -nE 'full gate|full repo gate|--full' -- z-nile/skills z-nile/templates SETUP.md AGENTS.md | grep -v lessons/`: the remaining hits are the merge's, `land`'s and setup's, which stay).
(2) The Design changes the `done` row "with its failure and fixture sentences", but docs.spec pins only "runs the affected gate … on that tree". "A failing full gate rolls the tree back" and "it skips the full gate" can stay unpinned.
(3) The fixture has no `pickman/default.project.json`, because neither `gatefix.make` nor `engine.copy` writes one. So `touch` creates it containing `-- edit` (probe: `project.json exists before touch: false`, `content: -- edit`). Refute 003 F3's "valid for `.json`" is true only for an existing file, and the case passes through the read-failure path, not through a project file forcing.
(4) AC8's `promoted_unchanged` diffs only `pickman/tests/acceptance` and `z-nile/tests/acceptance`. Those are today's only two (`ls -d */tests/acceptance`), but the criterion says "no promoted spec".
(5) Review 003 F5 recommended a line saying the Solution's "CI" names a gate c0172 removed. The Solution still lists CI under `--full`, with no note.
Recommendation: (1) Change prompt.md line 9 to name the affected project gate, and `unsays` "covers the full repo gate". (2) Pin the two sentences' new wording, or say they keep "full" on purpose. (3) Write a valid project file in `setup` (`{"name":"x","tree":{"$className":"DataModel"}}`), so the append keeps it valid. (4) Diff `'*/tests/acceptance'`. (5) Add the note under the Scope decision.
Lesson: z-design/restated-rules-move-together

## Candidate lessons (for the lead)
- z-design: an Override list for a changed template or string is proven complete by running the whole affected suite on a prototype with the change in, not only by a grep. Specs pin rendered forms (a placeholder substituted, the label dropped) that a search for the template's text can't match. Why: c0239 design review 004 F1. Three rounds of grepping for the RC0 template text missed `c0120/homes.spec`'s `--project z-nile --full`, and one suite run on the prototype found it. Check: was the list of Overrides confirmed by a suite run with every changed string in place, and is that run recorded?
- zz-test: a case that expects `ALL` (or any fail-closed answer) names which rule produces it and uses an input that only that rule decides. Inputs that also trip an earlier, broader rule (here a forcing path) leave the narrower rule untested. Why: c0239 design review 004 F2. Every "outside the home" case used a forcing path, and dropping rule 4 kept stop.spec green. Check: for each fail-closed rule, is there an input that only it turns to `ALL`?

Verdict: changes
