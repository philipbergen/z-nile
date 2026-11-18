# Review 005: c0138 (design mode)
Inputs: prep worktree `prep-trail-compaction-reset` (base c199e8de, uncommitted prep): `c0138.md`, `check.sh`, `acceptance/{renamed,kept,docs}.spec.luau`, `experiments/mutants.py`, `prototype.patch`, `design-review-00{1..4}.md`, `design-refute-00{1..4}.md`, `harvest.md`. Prototype `proto-c0138` (20eb19ac): `git diff -- z-nile/engine z-nile/skills` is byte-equal to `prototype.patch`, and its `check.sh`, three specs and `mutants.py` are byte-equal to the prep's. `./zn capture c0138` (7769d615) and b37679dc (the Solution bullets). `z-nile/engine/{trail,ids,main}.luau` (`cmd.capture`, `cmd.compact`, `cmd.remap`), `z-nile/tests/run.luau`. `origin/main` 13969cce. `./zn lessons --when design --full`, the zz-review, z-design (and `checklists/chore.md`), zz-arch and zz-test skills.
Dropped from design-review-004: none. All six answers are real (below).

## What I verified
I ran one throwaway clone (`mktemp -d` under the scratchpad, origin removed). It was checked out at 13969cce, with `prototype.patch` applied and the prep's issue files copied in. I deleted it afterwards. Every command ran under `bounded.pl`. The machine's load average went from 24 to 59 (other sessions) after my first run, so I stopped running specs, as the brief says. The mutants below that I didn't run are judged by reading.

- **No base drift.** `git diff --stat 20eb19ac origin/main` (172 commits) is empty over `z-nile/engine`, `z-nile/skills/zz-rules`, `z-nile/tests/lib`, `z-nile/tests/run.luau`, `z-nile/lib`, `zn`, `tests/lib`, `scripts`, `z-nile/projects.toml` and the c0111, c0114, c0119 and c0120 acceptance folders. `prototype.patch` applies cleanly to 13969cce.
- **The prototype passes on today's main.** `./zn check c0138` passes 4/4 in the clone (2 min 26 s under load).
- **Size 110.** The patch has 118 `+`/`-` lines, minus 8 file headers: 110 changed lines.
- **Round 4's answers are real.**
  - F1: `mutants.py` finds `acceptance/` beside itself, else the promoted folder. It prints its backup folder first and restores on SIGTERM and SIGINT. Steps 1 and 3 call it through `./zn find c0138`, which prints `z-nile/.tracker/issues/c0138`.
  - F2: `broken` edits c0010's review file (kept.spec:141). The first-review case expects `{compact} M`, `{broken} M`, `{prep} A`. M17 is in the runner and in the Rules table.
  - F3: E5 marks the "can't be read, first" cell as not built, with a reason that is true (the loop never tests a file by name).
  - F4: step 1's two triggers are independent ("do both") and name `projects.luau` and all of `z-nile/engine`.
  - F5: I reran the three pasted searches. They give 2 trail readers, 16 `zz-rules` readers and 12 `ids` loaders, as written. The counts check out: 18 `capture(` calls; 18 kept cases (setup plus 17); 26 mutants in the runner and in the table.
  - F6: `./zn lessons --uncovered c0138` reports every finding covered. The `check` sharpening is the lead's, as the refute says.
- **Scope fidelity (independent).**
  - Title and Problem equal the capture. The Solution bullets equal b37679dc's.
  - The whole-map reading resets a superset of what the literal `+`-line reading resets:
    - The `+` lines of an added or modified file are a subset of its lines.
    - A `+` line that fails to parse, or repeats an id, makes the whole file fail too.
    - A deleted map is read by neither reading.
    - A commit whose map file changes type (T) is no cut and is not read by either.
  - Both captured fixture outcomes have cases: c0010's capture and first review are found across the compaction, and done c0020, reused at the same path, stops there.
  - Nothing is narrowed.
- **Overrides: none. Confirmed.** AC4's three promoted specs pass. The design's other claims hold:
  - `cmd.capture` is the only caller of `trail.read` (main.luau:5282).
  - The `design-review-001` lookups in `metrics` read the files, not git.
  - c0136's in-flight `sources.spec` uses only `trail.isDoc`.
  - c0166 only names `trail.luau` as an area.
- **Other branches, rerun this round.** I re-listed every `.worktree/*` that changes the Touched files.
  - The `impl-` branches of c0117, c0118 and c0121 don't touch `trail.luau` or `ids.luau`. The `proto-c0117/0118/0121` hits are old-base trees where the files are new.
  - c0117's committed `prototype.patch` has a stale `trail.luau` hunk, the reverse of c0114's `dirs` default. That is c0117's base, not its intent: its impl branch doesn't carry it.
  - A three-way merge of this chore's `SKILL.md` and lesson versions against those of impl-c0117, impl-c0118, impl-c0121, proto-c0144, proto-c0172, proto-c0194, proto-merge-past-tracker-only and R0061 has 0 conflicts each.
  - c0118's appended lesson paragraphs agree with the new rule.
- **Restated rules.** `git grep` for "not followed", "changed the compaction" and "compaction" near history, life, capture or trail, over every skill, README and AGENTS.md, finds only the five places the Design names. `docs.spec`'s phrases equal The new sentences word for word.
- **Repository safety.**
  - `kept.spec` writes only in its `.cache` fixture (scripts and commits through `other`).
  - `renamed.spec` runs read-only `git diff-tree` on a non-commit in the real checkout.
  - `docs.spec` reads only.
  - `check.sh` runs only `tests/run`.
  - The runner edits the executor's engine files and restores them. It is an experiment, not a check, and is named so in steps 1 and 3.
- **New mutants, beyond the runner's 26.**
  - Run: `mutants.py M18` (a name that matches nothing) runs no mutant and prints "all mutants killed", exit 0 (F1).
  - Reasoned (not run because of the load), each killed by an existing case:
    - X1, the memo keyed by the map file (`cuts[sha]`) instead of the sha: `compact2` and `compact` share a slot. c0020 then reads `{}` at `compact` and loses its restart, which fails the c0020 cases.
    - X7, "a compaction that renames nothing is no cut" (decided per commit, not per id): `compact` renames others, so kept c0010 restarts there and the c0010 case fails.
    - The map read from the working tree, or at `head`: both make every cut reset or every rename vanish, and the c0010 and c0020 cases catch either.
    - `renames` reading only the file `cuts` reported (the first, alphabetically) is MA: `both` kills it.
    - Concatenating the maps before one parse: renamed.spec's "two maps that repeat a new id are each fine" kills it.
  - Equivalent, no case needed:
    - `--root` dropped: a root commit can't rewrite a kept item in place, and the nil answer resets anyway.
    - `--no-renames` dropped: `diff-tree` does no rename detection without `-M`.
    - `resets` comparing with `~= nil`.
- **Executability.** I read steps 1 to 5 as an executor with only this folder. Each command runs from the repository root of the execution worktree. The patch applies, and nothing asks for a decision. The one weak spot is the runner's verdict (F1).

### F1 [low] The mutation runner's "all mutants killed" can't fail for a mutant that breaks loading, or for a named run that matches nothing, and the steps require it to mean "died on an assertion"
Where: `experiments/mutants.py`, lines 113 to 117 (`fails = [l for l in out.splitlines() if l.startswith("FAIL")]`, then only the `FAIL` lines are printed, cut at 150 characters) and line 95 (`only = sys.argv[1:]`). Implementation steps 1 and 3 ("every mutant must die on an assertion"; "exit 2 means a mutant's edit no longer applies…: fix that edit, never skip it"). z-design's Mutation check ("must fail on an **assertion**, not a syntax or require error").
Evidence:
- A load error counts as a kill. `z-nile/tests/run.luau:308` prints `FAIL {file}: could not load spec: {spec}` when a spec can't be required. A mutant edit that leaves `trail.luau` unparseable makes `renamed.spec` print that line, so the runner records a kill. In `kept.spec`, `./zn capture` exits non-zero and each case fails on `expect(r.code).toBe(0)`, so the error even looks like an assertion there.
- The executor can't see the cause. A case failure prints `FAIL {file} :: {case}` with the error on the next line (`run.luau:320`). The runner keeps only the `FAIL` line, so the error message that would tell an assertion from a crash is dropped.
- A named run can pass vacuously. In the clone, `python3 -I …/mutants.py M18` ran no mutant and printed `all mutants killed`, rc 0.

Critique: step 1 tells the executor to fix any mutant edit that no longer applies after drift. That hand-fixed edit is exactly the one most likely to be a syntax error, and the runner would then report it killed. The prep's own runs are not in doubt: every row's kill was traced to its named cases in rounds 1 to 4. The risk is the executor's re-run being false comfort. The tempting fix is to print more lines. That still leaves the verdict to a human reading 26 blocks.

Consequences:
- A load check needs a way to load the mutated module that is cheaper than a spec run. `renamed.spec` already requires `trail`, so its `could not load spec` line is that check.
- Refusing unknown names adds one refusal message.
- On SIGTERM, the `lune` child runs in its own session (`start_new_session=True`). The handler restores the files but leaves the child running for up to 240 CPU seconds. That is CPU the user cares about.

Recommendation:
- In `mutants.py`, treat a `could not load spec` or `worker exited` line as "broken mutant, not killed": print it and exit 1 ("fix the edit").
- Print the line after each `FAIL` (the error text) so a kill can be read as an assertion (`expected …`).
- Exit 2 when an argument names no mutant.
- In `on_signal`, `os.killpg` the running child's group before exiting.
- Rerun one mutant to see the output.

All of this is experiment code (not sequestered, not counted in size), so no Rules row or spec changes.
Lesson: zz-test/no-vacuous-pass (its `check`: "Can this check pass because it found nothing to check…").

## Lesson candidates (for the lead)
- **A mutation runner's verdict separates "killed on an assertion" from "broke the build"** (a note on z-design's Mutation check, or zz-test/no-vacuous-pass). The executor re-runs it after hand-fixing edits that drift moved, and a broken edit then reads as a kill. Check: make one mutant a syntax error. Does the runner report it as broken rather than killed? And does a run whose names match nothing fail?

Verdict: approve
