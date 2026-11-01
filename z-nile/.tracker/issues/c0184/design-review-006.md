# Review 006: c0184 (design mode)
Inputs: the prep worktree `prep-scaffold-arcade-homes` at 5a67dca7 (synced with main), with its uncommitted c0184 folder (c0184.md, check.sh, acceptance/{homes,generic,docs,skills}.spec.luau, experiments/, design-review-001..005, design-refute-001..005, harvest.md). Today's origin/main is b6a6f538 (`git ls-remote`).
Dropped from design-review-005: none open. F1 to F4 hold (ruled below).

Replay on today's main. In a throwaway clone of b6a6f538 (a bare clone as `origin`), I copied the worktree's c0184 folder in, then ran Implementation steps 2-3 as written, in a linked worktree (as the executor will be, because `./zn skills` refuses the main checkout):
- `home.luau` and `homespec.luau` copied, then `scaffold-homes.sh`, then the skills copied, then `./zn skills` (10 links), then `git apply tooling.patch`, which applied with no hand hunks.
- `stylua --check` over the 57 changed or new `.luau` files: clean.
- `rehash.py`: `d5634735 -> d5634735`. The patch already carries the recomputed digest, so the step is a no-op on a clean apply.

What main brought since the prototype base. Main differs from 74a78154 (c0183's prototype) outside tracker roots only by `z-nile/next`, nine lesson files and c0183's four promoted specs (`git diff --stat proto-base main -- . ':!*/.tracker/**'`). None of these is a file the patch or the experiments touch, and the homes' `.tracker/` files are identical.

Every spec run below is on main plus c0184, committed:
- **AC9's and AC5's overridden set**: c0172 narrowed, c0115 layout, docs, absence and readme, c0114 docs, c0120 docs, layout and graph-homes, c0111 skill-docs, c0006 clone: 67/67.
- **AC9's other specs**: c0114 gate-cover, c0120 ci, tooling repo-fence, c0077, c0005, c0115 skills, prompt and lessons, c0067 ready, c0111 prompt-lessons: 111/111.
- **c0184's four specs plus c0183's four**: 23/23.
- **Item 4's search.** I ran `git grep -lF` with each Touched path and its basename, plus `pickman/skills`, `pickman/tests`, `"pickman/"` and `"pickman"`, over `*/tests/acceptance`, `z-nile/tests/{tooling,meta}` and `pickman/tests/meta`: 148 files. The matches by pattern are in my notes. Those that read the real tree and weren't run above:
  - c0116 docs, c0048 board-docs, c0052 and c0081 skill-doc, c0057 open, c0107 keep, c0119 scope-docs, c0127 skill, c0172 merge, c0115 and c0120 freeze, c0111 lesson-format and harvest, lessons-hidden, z-nile's meta architecture: 82/82.
  - c0120 finished, check-paths, gate-homes, homes, old-roots, registry-home and runner-home, c0114 finished, layout and registry, c0049 spec-isolation, fence-every-home, affected: 96/96.
  - From `pickman/`: meta architecture, fence and the new home spec, c0041 src-aliases and graph-build (which read `.luaurc`), c0003 pipeline, c0064 docs, c0015 workflow, c0002 affected-place: 47/47.
  - The rest are fixtures or history (c0154 `durations.luau`, frozen path lists, `"--project", "pickman"` arguments).
- **The homes, the AC hand runs and promote-check**:
  - `snake`, `arcade` and `portal` (`lune run tests/run`): 20/20 each.
  - `places.luau`: exit 0. `./zn skills --check`: ok.
  - AC6 and AC7 run by hand (their grep parts): pass. AC8: pass. The root `.luaurc` has no `logic` or `shared`.
  - `./zn promote-check c0184`: OK.
  - `./zn lessons --uncovered c0184`: every finding covered. `./zn lessons --check`: ok.

Not run, by the CPU rule: any `--full`, any home's `check.sh`, or AC2's plan. No gate file changed on main since round 5.

Round-5 fixes, ruled on:
- **F1 holds.** narrowed.spec is green with the recomputed digest. `rehash.py` turns the old `a9c5f2a2` back into `d5634735`. I also appended a probe comment to c0120 docs.spec with CRLF, `c0999`, `f12_x`, `R7`, `xc0120`, `(c0120)` and a non-ASCII character. After `rehash.py` (`-> 0803ddbf`), narrowed.spec passed (1/1), so its masking and newline rule match the spec's `exact`. c0115 layout is green, and its two round-5 mutants each fail it: a `snake-arch` link to `../../z-nile/skills/snake-arch`, and `.claude/skills/portal-test` removed (both committed, both red).
- **F2 holds.** c0115 docs and absence read the registry. Round 5's wider search, rerun on the patched tree (`git grep -nE 'pickman/(skills|tests|scripts|src)|"pickman/"|"pickman"|isDir\(.pickman' -- z-nile/tests z-nile/engine z-nile/lib scripts zn pickman/tests ':!z-nile/tests/acceptance/c0184'`), leaves only these hits:
  - fixtures;
  - history: `main.luau:2432/2459` (the c0120 and c0115 freezes) and `skills.luau:408` (the rename map);
  - c0114 gate-cover:134, a contains-check on the Lune-types line, which AC2 extends for the new homes;
  - absence:138, the `code()` docs exemption. The new homes' skills are `.md`, so they are excluded anyway.

  Mutants run: a snake-arch Lessons paragraph without the real-folder clause fails c0115 docs and c0111 skill-docs. A `.claude/skills/testing/` path in `snake/src/server/Main.server.luau` fails both absence cases.
- **F3 holds** (the Checklist says ten and one digest).
- **F4 holds** (homes.spec has the `two` and `open` maps, pinned by prefix and path).

### F1 [low] The Rules and mutants table has no rows for the overrides added in rounds 4-5 or for the two deps-block outcomes, though round 5's answers say their mutants were run
Where: c0184.md Rules and mutants (the one row "the promoted rules cover the new skills and homes" names only c0111 skill-docs, c0115 readme and c0006 clone); E17; design-refute-005 F1, F2, F4.
Evidence: these have no row: the c0114 and c0120 docs widenings, c0115 layout (round 5 F1's two mutants), c0115 docs and absence (F2's two mutants), and homes.spec's doubled and unclosed deps blocks (F4's "opening fences counted only"). E17 names only "the unclosed and the doubled deps block". The cases themselves kill the mutants. I ran four (above), each red.
Critique: zz-review item 0 requires a row per behavioural rule. A rule without a row is the one the next author narrows without knowing a case held it.
Consequences: none beyond the table.
Recommendation: add rows, marked `run: killed`:
- c0115 layout: "a skill's link goes to its own project's folder; every project's skill has one";
- c0115 docs: "every project's skill names the real lessons folder";
- c0115 absence: "every home's live files are scanned";
- c0114 and c0120 docs: "their skill rules read every project's skills";
- homes.spec: "one closed deps block".

Each row takes the mutant above, or this review's run as its record.

### F2 [low] A stale sentence after the digest paragraph says "Neither is digest-pinned by c0172's narrowed.spec"
Where: c0184.md Regression guard, the line after "The digest: …" ("Neither is digest-pinned by c0172's narrowed.spec (its list has c0114's `layout.spec`, a different file); c0183's overridden specs are not touched again.")
Evidence: the sentence dates from when the `Overrides:` line held only the two alias cases (c0120 layout and graph-homes). It now follows a paragraph saying one of the ten (c0120 docs) is pinned, so "Neither" reads as a contradiction. The claim is true for the two alias specs: narrowed's 15 rows, listed from the file, hold c0114 layout and c0120 ci, not c0120 layout or graph-homes.
Recommendation: write "No other overridden file is in c0172's list (its 15 rows hold c0114 `layout.spec` and c0120 `ci.spec`, not c0120 `layout` or `graph-homes`)". Rerun `grep -nE 'Neither|None is in' c0184.md`.
Lesson: z-design/restated-rules-move-together

### F3 [low] check.sh AC9 names c0115 `docs.spec` and `absence.spec` twice each
Where: check.sh AC9 (line 3 has `c0115/docs.spec.luau`, line 5 has `c0115/absence.spec.luau`, and line 7 has both again).
Evidence: the runner doesn't deduplicate. `lune run tests/run -- …/absence.spec.luau …/absence.spec.luau` prints `12 passed, 0 failed, 2 spec files`. It's harmless, but each copy costs a run at every `./zn check`, and it reads as if a different spec was meant.
Recommendation: drop the second copies, and check that no intended spec is missing. Each of the ten overrides plus narrowed is in AC9 or AC5; I compared the two lists.

Verdict: approve
