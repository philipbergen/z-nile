# Review 001: c0301 (design mode)
Inputs: 4c487268fa036b3d9ddff84974c9dc1a74b908cb (prep draft); `z-nile/.tracker/issues/c0301/c0301.md`, `check.sh`, `acceptance/{claims,code,land,docs}.spec.luau`, `experiments/{prototype.patch,mutants.py,run-plain.sh}`; `./zn capture c0301` (capture 17110f8d, no marker); `z-nile/engine/trace.luau`, `main.luau` (`traceProblems`, `cmd.finish`, `touchedModules`), `raftplan.luau`, `spend.luau`, `z-nile/lib/watch.luau`, `z-nile/tests/lib/seal.luau`, `z-nile/tests/tooling/stack-fix.spec.luau`, `z-nile/tests/acceptance/c0330/stub.spec.luau`; zz-rules, zz-arch, zz-test, z-design. `git diff 126f0716 origin/main -- z-nile/engine z-nile/lib z-nile/tests` is empty (base unchanged).

Ran: `./zn check c0301` on the unchanged tree. 1/5 passed: AC5 passes; claims 0/6, code 1/8, land and docs fail on assertions or on the functions the design adds, as E1 records. I also ran a pure probe of `trace.check` on the prototype (`prototype.patch` applied to copies of the six files under `.cache/c0301-review`, run with `./zn run --time 60 -- lune run …`, removed afterwards). Its output is quoted in F1 and F2.

Checked and found sound: the scope matches the capture (Problem and Solution unchanged; the three `(Added in prep)` Non-goals move no captured outcome, and every S claim has a Checked AC). The Rules and mutants table has a row for every rule I found, and each spec case can fail. Repository safety holds: code and claims are pure, land works in a `trackerfix` fixture under `.cache` committing as `@example.invalid`, docs only reads. `Overrides: none` holds: c0330's `stub.spec` AC6 pins on the zz-rules `trace` row survive the new wording, and no promoted spec pins the changed message. `seal.trace` reading only the finish commit is safe: `./zn finish` squashes the layer (`reset --soft base`), so that commit holds every file the layer changed.

### F1 [high] A tests-only ticket whose layer only deletes spec files can never pass the check in a source-changing stack, which is a regression and leaves captured S2 unmet
Where: Design, Rule 2 (`trace.testsOnly`, the code-cell bullet and the "Order of the branches" bullet); AC2; Existing work (`seal.trace`'s `testsOnlySpec`)
Evidence: `testsOnly` counts every spec path in the layer's `diff-tree --name-only` list, and that list includes deleted files. Take a layer that only deletes `pickman/tests/unit/old.spec.luau` and its watch file, in a stack where another ticket changed `pickman/src/alpha.luau`. On the prototype, `trace.testsOnly(...).c0020` is `true`, and each cell that ticket could write is refused:
- `old.spec.luau:1` gives `row c0020:P1, code: pickman/tests/unit/old.spec.luau:1 does not exist at commit`, because the file is gone at the top commit;
- `pickman/src/alpha.luau:2` gives `row c0020:P1, code: ticket c0020 changed no source file; pickman/src/alpha.luau is not a spec file it touched`;
- `none` gives `row c0020:P1, code: "none" is only valid when the stack changed no source file`.

Today the same row passes by citing the changed source, so `./zn done` now refuses a stack that lands today. `seal.trace` breaks the same way: `testsOnlySpec` returns nil when no spec still exists, so the row cites the first changed source and is refused.

This is not an exotic layer. The Overrides flow ("promoted specs this issue deliberately changes, each with its chore", in `depends_on`) pairs a source-changing ticket with a chore that rewrites or deletes the promoted spec pinning the old behaviour. The deleting kind is exactly this layer, and #309 deleted thirteen promoted specs. Captured S2 also covers the case literally: a deleted spec is "a spec file that is in that ticket's Touched modules and that the stack changed", and the design refuses it.
Critique: the tempting fix is to let a tests-only ticket write `none`, but the captured Non-goal keeps `none` only for stacks that changed no source file. The other tempting fix is to call a ticket with no spec left "not tests-only" so it borrows a source line again. That drops S2 and S3 for those tickets, which is a scope cut.
Consequences: a deleted spec has no line at the top commit, so a rule that accepts it needs a second text to check the line against. A spec that a lower layer added and this layer deleted is not in `git diff <main> <top>` at all, so S2 ("that the stack changed") does not promise it.
Recommendation: keep the scope and let a tests-only ticket cite a spec its stack deleted, at a line the file had at the stack's base:
- **Adapter.** `traceProblems` reads every `isSpecFile` path in `diffList` that is absent at `topTip` with `git show <baseTip>:<path>`. A path the base..top diff lists as deleted always exists at `baseTip`. The texts go into a new `CheckInput.filesAtBase: { [string]: FileMeta }?`; nil means no deleted spec can be cited.
- **Check.** In the tests-only branch, a ref that is absent from `filesAtCommit` but present in `filesAtBase` gets its line checked there. The finding for a bad line is `row <cid>, code: <path>:<n> does not exist at the stack's base (the stack deleted it)`. The spec-file, `changedFiles` and own-layer-or-Touched tests then apply unchanged. Non-tests-only tickets keep the spec-file message for any spec, deleted or not.
- **Fixture filler.** `seal.trace`'s `testsOnlySpec` cites the first spec in the finish commit whether or not it still exists, as `<spec>:1`.
- **Degenerate stack.** A spec that a lower layer added and this layer deleted keeps the `was not changed by this stack` finding. State that in the Design.
- **Docs.** The contract, the zz-rules row and the zz-review bullet say "or one the stack deleted, at its line on main". docs.spec pins that wording.
- **Spec cases.** In code.spec, a deletion-only tests-only layer in a source-changing stack: `old.spec.luau:1` passes with `filesAtBase`; `old.spec.luau:9` fails naming the row; `alpha.luau:2` and `none` fail. In land.spec or a new real-git case, a layer that deletes a spec: `--check` passes citing `<deleted>:1`, and `seal.trace`'s table passes.
- **Rules and mutants rows.** `filesAtBase` ignored; `filesAtBase` consulted for a path that still exists; the base text read at `topTip`.

If the author prefers the borrowing fallback instead: escalate to the user. The choice is "a ticket with no citable spec keeps today's rule". Its cost is that S2 and S3 no longer hold for deletion-only tickets, and it needs a `Scope decision (user, …)` line.
Lesson: z-design/new-rules-migrate-existing-work

### F2 [medium] The Touched-modules half of rule 2 never matches an entry written relative to the project's home, which is how most project tickets write them
Where: Design, Rule 2 (`inTouched`: "equal to or under (by whole path components) one of its Touched modules"); AC2
Evidence: pickman's and the games' issue documents hold 261 Touched paths written relative to the home (`src/…`, `tests/…`, `.tracker/…`) and 110 written from the repo root. The home-relative ones include `src/shared/Logic/Best` and `tests/unit/Session` in f0148, and `tests/acceptance/f0104/keys.spec.luau` in the done spec-fixing chore c0150, all from 2026-09 and 2026-10. The template's own comment gives `tests/unit/Maze` as its example. Code cells and `changedFiles` are repo-relative (`pickman/tests/...`). On the prototype, a pickman ticket c0020 whose Touched names `tests/unit/alpha.spec.luau`, citing `pickman/tests/unit/alpha.spec.luau` changed by c0010's layer, gets `row c0020:P1, code: pickman/tests/unit/alpha.spec.luau is neither changed by ticket c0020's layer nor in its Touched modules`. The repo-relative control passes. So captured S2, a spec "in that ticket's Touched modules", fails for the way most project tickets write that section, and the message tells the lead the spec is not in Touched modules when it is.
Critique: the tempting fix is to tell authors to write repo paths. Hundreds of written documents and the template's example say otherwise, and nothing enforces it.
Consequences: matching both forms means an entry is tried as written and as `<home>/<entry>`. A z-nile entry already starts with `z-nile/`, so its joined form never exists and matches nothing. Neither form can match a path in another project's home by accident, because both are compared by whole components. The rule for `home == "."` (no prefix) must be stated.
Recommendation: `inTouched(path, touched, home)` accepts a path equal to or under, by whole components, either the entry or `home .. "/" .. entry` when `home ~= "."` (`IssueDoc.home` is already in the input). State this in the Design and the restated rules. Add code.spec cases:
- an entry relative to the home (`tests/unit/alpha.spec.luau`, a pickman issue) passes;
- a home-relative folder entry (`tests/unit`) passes;
- an entry that only shares a prefix once joined (`tests/unit/alp`) fails.

Add mutant rows for "entry as written only" and "plain prefix after the join".

### F3 [medium] The Design claims Touched modules has one reader, but `spend.ownedPaths` keeps its own reader with a different grammar
Where: Design, Rule 2's Touched-modules bullet ("so z-raft's plan, the workstreams and the trace read the section with one function (zz-arch, one reader per format)"); Maintainability ("One reader per format: … Touched modules (`raftplan.touchedModules`…)"); AC4 and docs.spec (only `main.luau` and `trace.luau` are checked)
Evidence: `z-nile/engine/spend.luau:55-65` reads the same section with `"\n#+%s*Touched modules[^\n]*\n(.-)\n#"`. It accepts any heading level and a suffixed heading, takes every backticked path in the section rather than the head of each bullet, drops paths without `/`, and strips comments first. `raftplan.touchedModules` requires `### Touched modules` exactly, reads only the first backticked path at the head of a bullet, and keeps `zn`. So "- `a/x.spec.luau`, `a/y.spec.luau`" credits both paths to the ticket in spend, and only the first is a Touched module for the trace. zz-arch rule 5 says each format has one reader and every command uses it. The design newly gives the section a gate's meaning (which spec citations pass) while a second reading of it stays.
Critique: the tempting fix is to say AC4 only scopes `main.luau` and `trace.luau`. Then the Maintainability claim stays untrue, and the next reader of the section has two grammars to pick from.
Consequences: moving spend onto `raftplan.touchedModules` changes spend attribution in `./zn metrics` for documents written outside the one-path-per-bullet grammar, adds a `spend → raftplan` edge (no cycle: raftplan requires only `@lune/serde`), and puts `spend.luau` in Touched modules and its specs under Affected specs.
Recommendation: make `spend.ownedPaths` call `raftplan.touchedModules(text)`, keeping its `/` filter as a post-filter if attribution needs it. Widen AC4 and docs.spec to say no engine file other than `raftplan.luau` matches the heading pattern. Add a spend case that pins the attribution of a fixture document. If the author rules the attribution change out of this ticket, correct the two sentences so they name spend's reader as the remaining second reader, and capture an issue for it.

### F4 [low] Existing work misses R0101, a second active raft with a filled `trace.md` holding "None." rows
Where: Design, Existing work
Evidence: `origin/R0101/2/c0177:pickman/.tracker/rafts/active/R0101/trace.md` has `c0176:AC3: None.`, `c0176:AC4: None.`, `c0177:AC3: None.` and `c0177:AC4: None.` (code `none`: a stack that changed no source file). The Design names only R0100 and R0093.
Critique: R0101 ends up the same way as R0100. After a restack onto a `main` that has c0301 the table is stale and refilled, and a kept row is `unknown claim`. Nothing breaks, but the list the lesson asks for is incomplete.
Consequences: none.
Recommendation: add R0101 to Existing work beside R0100. Say how the list was made (every `rafts/active/*` on `origin/main` and every `origin/R*/…` layer tip checked for `trace.md`), so the executor can rerun it at step 1.
Lesson: z-design/new-rules-migrate-existing-work

### F5 [low] The experiment record does not say the probes ran bounded, and the mutation script calls a runner that is not committed
Where: Unknowns & experiments (E1 to E6); `experiments/mutants.py`
Evidence: no experiment says it ran through `./zn run --time`. `mutants.py` bounds each spec with Python's `subprocess.run(..., timeout=600)`, which kills only the direct child, not the runner's fixtures and `git` children. It also calls `/tmp/c0301-run.sh`, not the committed `experiments/run-plain.sh`, so E6 cannot be rerun from the files in the item.
Critique: item 12 asks whether the probes ran bounded. The record cannot answer that, and a rerun of `mutants.py` as written would start unbounded grandchildren.
Consequences: none.
Recommendation: record in E1 to E6 that each run went through `./zn run --time <s> --`, or say it did not. Make `mutants.py` run each spec as `./zn run --time 600 -- experiments/run-plain.sh <spec>` with the committed script.

Verdict: changes
