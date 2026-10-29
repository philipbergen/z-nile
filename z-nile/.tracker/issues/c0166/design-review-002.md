# Review 002: c0166 (design mode)
Inputs: prep worktree `prep-relevant-review-lessons` at 53de68b4 plus its uncommitted working tree: `c0166.md`, `check.sh`, `acceptance/*.spec.luau` (7), `named-areas.spec.luau`, `harvest.md`, `design-review-001.md`, `design-refute-001.md`, the 14 edited lesson files and the new `z-design/lessons/filter-proves-recall.md`. Also read: `./zn capture c0166` (3e349d10, no marker); `lune run z-nile/affected -- <path>` for every engine, skill, template and gate Touched path (all `ALL`), and `grep -rlF -e <path> -e <basename>` over `z-nile/tests/acceptance` and `pickman/tests/acceptance`; `./zn lessons --skill zz-review --full`; `./zn lessons --when design --full` (130 checks). `--for` is an unknown option in this worktree's engine (`unknown option --for`), so I used the unfiltered list. Code read: `z-nile/engine/lessons.luau` (exports, `Tree`, `check`, `select`, `load`), `main.luau` (`flags`, `cmd.lessons`, `raftDesignRounds`), `store.members`, `tests/lib/trackerfix.luau`, `tests/lib/engine.luau` (`copy`, `clearLessons`); promoted specs c0084 `commit-phase`, c0111 `harvest`, `lessons-cli`, c0114 `trail-move`, c0115 `lessons`, c0116 `issue-design`; `.github/workflows/check.yml`; zz-arch rule 4; the zz-test sequestration rules.
Scratch runs, none touching the repository (scripts in `/tmp/c0166rev`):
- a git demo of the merged-main case's fixture steps;
- a Python emulation of `relevant`/`select`, using the Design's area table and mode lines, over the live lesson tree and the issue and raft harvest ledgers;
- `git diff $(git merge-base <b> origin/main) <b> -- '*harvest.md'` over every `origin/prep-*` and `origin/R*` branch;
- a count of `design-review-NNN.md` and `review-NNN.md` files in every unfinished item folder.

Dropped from design-review-001:
- F1, F2, F3, F4, F5, F8, F9, F11, F12, F13 and F14. Each fix is in the text, and the specs now carry the cases those findings asked for (members at four and four, the project-relative path, `since check`, the 4-word bound on both sides, the backticked c0117 pin kept, the data-file table).
- F1's remaining gap is a different mechanism (which skill a path exercises), so it is a new finding, F8.
- F6 and F7 are repeated as F3, and F10 as F7.

### F1 [high] Nothing passes the area table to `relevant`, `select` or `check`, but the specs need them to use it
Where: Design, Selection (signatures of `lessons.relevant`, `lessons.select`), Area table ("`lessons.load` reads it. `lessonareas.parse` is the pure parser"), `lessons.check` paragraph; Implementation step 1 ("no second copy of the table"); `acceptance/relevance.spec.luau`, `acceptance/parse-check.spec.luau`
Evidence:
- The specs call `api.relevant(core, maze, folders["zz-review"])`, `api.relevant(fence, { "z-nile/lib/fence.sh" }, nil)`, `api.relevant(acc, { "pickman/.tracker/issues/f0001/acceptance/x.spec.luau" }, nil)` and `api.select(all, {}, q, folders)`. They expect `review` to be core, `fence` to map to `z-nile/lib/fence.sh`, `tracker` to `z-nile/engine`, and `acceptance` to `@item`.
- parse-check's hand-built `tree(...)` has no table field. Even so, `lessons.check(withFolders)` must report `unlisted tag not-a-tag` and must accept `wiring`.
- The signatures in the Design take no table: `relevant(lesson, paths, skillFolder)`, `select(all, sources, q, folders)`. `Tree` and `Query` gain no `areas` or `core` field.
- The Design says the only reader of the file is `lessons.load` (the edge), and `lessonareas.luau` holds "no second copy of the table".
- That leaves two ways to pass these specs: `lessons.luau` reads `z-nile/skills/lesson-areas.md` itself (from which directory? specs run from `z-nile/`, the CLI from the repository root), or the table is hard-coded in Luau. The first breaks zz-arch rule 4 ("pure over texts, reads at the edge") and the Design's "No file is read to decide a match". The second breaks step 1.
- This is a hole in review 001 F11's fix. Moving the table out of code left no way for it to reach the pure functions.
Critique: The executor can't satisfy both the specs and the Design. The fix they will reach for is a module-level `lessonareas.TABLE` loaded on first require. That is a hidden read in a pure module, and it makes every pure case depend on the live file (F7).
Consequences:
- Passing the table explicitly changes three signatures and the `Tree` type, and the specs change with them.
- The CLI fixtures copy `z-nile/skills/` from the real checkout (`engine.copy`). So the fixture's rows are today's rows unless the fixture seeds its own `lesson-areas.md`.
- A missing or unparseable file now needs a defined result (F9).
Recommendation:
- Give the parsed table an explicit route: `Tree` gains `areas: lessonareas.Table?` (set by `load`). `relevant(lesson, paths, skillFolder, table)` and `select(all, sources, q, folders, table)` take it. `lessons.check` uses `tree.areas`, and a tree with `areas == nil` gets no unlisted-tag or `@item` behaviour, as it already does for `folders == nil`.
- Rewrite relevance.spec and parse-check.spec to build their own small table with `lessonareas.parse("core: review\nfence: z-nile/lib/fence.sh\n…")`.
- Add a case: the same lesson and path give a different answer under two different tables. That kills the "table hard-coded" mutant.
- Add a Rules row for it.
Lesson: zz-arch/one-reader-per-format

### F2 [high] Four sequestered cases fail an implementation that follows the Design
Where: `acceptance/prompt.spec.luau:72`, `acceptance/rewrite.spec.luau:165`, `acceptance/rounds.spec.luau:180`, `acceptance/rewrite.spec.luau:96`; Design lines 78, 172, 178; Unknowns E2/E3 (the cases are `reasoned`, never run)
Evidence:
- **prompt.spec "omits a build lesson that does not overlap them".** Line 172 says `buildLessons` "passes `exercised` for mode `code`". AC7 says "including mode `code`". The mode line for code is `zz-execute, zz-review, zz-test`. The case's dropped lesson is `zz-test/wire` (`when: build`, a zz-test lesson). Mode code keeps it, but the case asserts `has(s, "zz-test/wire") == false`.
- **rewrite.spec "introducing commit".** This case runs last, on branch `R0001-lessons`. By then "a lesson that does not parse" has committed `zz-test/bad.md` (`when: never`) by plain git on that branch. Line 178: "A lesson file in that same delta that does not parse is `commit: <id> does not parse` from `./zn commit`". The delta is merge base (seed) to index, so it contains `bad.md`. `./zn commit("introduce fresh")` must refuse, but the case requires exit 0. The case fails under every reading of the stale rule, because pin, aaa and zzz are also stale under the reading the spec itself uses (F3).
- **rounds.spec "a missing lesson id".** `harvest.md` holds `NOTE` (valid ids), then a second note naming `zz-test/missing`. Line 78: "satisfied only when some bullet … and some note line is `- note 5 …`, … every id parses …, and every id is in `known`". `NOTE` is such a line, so the loop is satisfied and the commit is allowed. The case asserts `missing.code == 1`. Only an "every note line" reading passes, and no pure case has two notes.
- **rewrite.spec "uncovered reports a plain commit".** The Design says this is not stale, and the spec says it is. Detail in F3.
Critique: An executor may not edit these specs. Each one stops the raft, or pushes the executor toward the wrong rule to turn it green. All four are rows the round added as `reasoned`. They were written against a text no prototype has run.
Consequences: Fixing each case alone leaves the next contradiction for round 3. The prototype the Unknowns already call for ("The next prototype runs `z-nile/check.sh --full` … before `design: ready`") is the step that finds them.
Recommendation:
- prompt.spec: make the dropped lesson one from a skill outside the code set (for example `zz-arch/wire`), and keep a `zz-test` lesson that mode code must keep.
- rewrite.spec: give "introducing commit" its own fixture, or remove `bad.md` and fix the stale lessons before it runs. Also add a case where `./zn commit` refuses because of `bad.md`. That rule has no `./zn commit` case today, only `--stale`.
- rounds: state "every matching note line's ids exist" in the Design, and add a pure case with a valid note first and an invalid note last (zz-test/any-rule-places-the-decider-first-and-last).
- Then build the prototype of this text, run all seven specs and every `reasoned` mutant, and record the results in E2 before round 3.
Lesson: z-design/prove-specs-pass-on-a-prototype, z-design/spec-design-correspondence

### F3 [high] The stale check and `since check` read "recurred after its check" two different ways, and the spec expects the other one (repeat of design-review-001 F6 and F7)
Where: Design, Rewrite paragraph line 178 ("A lesson is stale when … the base count was greater than 0, and its `check:` line differs between the base and that tree"), metrics `since check`; `acceptance/rewrite.spec.luau:96`
Evidence:
- **The sentence is inverted.** It makes a lesson stale when its check *differs*. `needsRewrite` (line 78) is true only when `not checkChanged`.
- **One rewrite clears the whole branch.** With the intended reading (stale when count(tree) > count(base) > 0 and check(base) == check(tree)), a branch that changes a lesson's check once is never stale for that lesson again on that branch. rewrite.spec shows the result:
  - Base: pin's check is "old", with 1 source.
  - "rewrite the check" commits "new" together with source 2.
  - "uncovered reports a plain commit" adds source 3 by plain git.
  - Now count(tree) = 3 > count(base) = 1, but check(base) = "old" ≠ check(tree) = "new", so the rule says not stale.
  - The case asserts `--uncovered c0001` exits 1 with `gained a source and its check line did not change`. Its own metrics assertion `later 2, since check 1` says the lesson recurred after its current check, which is the `since check` reading.
- **Lessons born on the branch are never checked.** A lesson introduced on the branch has base count 0, so it is never stale there. An issue that writes a lesson in round 1 and harvests the same lesson again in rounds 2–5 of one prep is never told to rewrite it. That is the loop Problem (b)'s "an ineffective one is rewritten" is about.
- This is the third hole found in this mechanism: review 001 F6 (where the refusal runs), F7 (what "rewritten" means), and now the base.
Critique: The tempting fix is to patch the sentence ("differs" to "is the same") and drop the spec case. That keeps a rule that lets a prep's fifth recurrence through.
Consequences:
- A single reading needs, for each source on the branch, the commit that added its harvest line (or the index, for `./zn commit`), and the commit that last changed the lesson's `check:` line. The Scalability section already pays this walk for `since check`.
- Merges stay harmless: a source whose line is reachable from the base is excluded, whichever commit brought it in.
- A lesson introduced on the branch has its introducing commit as the origin.
Recommendation: Define one function and use it in all four places (metrics `since check`, `--stale`, `--uncovered <id>`, `./zn commit`).
- A lesson is stale when it has a source that meets all three conditions:
  - its harvest line is not reachable from `git merge-base HEAD origin/main`;
  - it was added after the commit that last changed the lesson's `check:` line (for the index: the line is new in the index, and the check is unchanged from HEAD);
  - it is not the lesson's first source.
- `since check` is the same count without the base restriction.
- Fix line 178 to say so.
- Add cases:
  - a lesson introduced on the branch, then a later source by plain commit, is stale;
  - after a check change on the branch, a further source by plain commit is stale (the current rewrite.spec:96);
  - a later source in the same commit as a check change is not stale.
- Make the Rules rows name this function.
Lesson: z-design/one-reading-per-value

### F4 [high] The "merged main source" case passes without merging anything, so AC4's merge sentence has no failing case
Where: `acceptance/rewrite.spec.luau:145` "a merged main source is not stale"; Rules row "a source that arrives by merging main is not stale | … | the comparison is against HEAD"; AC4
Evidence:
- `trackerfix.elsewhere(g, …)` pushes "main adds a source" from `g.other` to the bare origin. Then the case runs `fixture.git(g.main, { "merge", "-q", "origin/main" })` with no fetch. `g.main`'s `refs/remotes/origin/main` is still the seed, so the merge is a no-op.
- I reproduced the same steps with plain git in `/tmp/c0166rev/m`: `git merge origin/main` printed `Already up to date.`, and the file kept the old line.
- So `harvest.md` in `g.main` never gains `design-review-002 F1`, there is no new source at all, and every implementation passes the case.
- Even with a fetch, the listed mutant ("comparison against HEAD") would not die. After the merge, HEAD contains the line, so HEAD-versus-tree has no delta either.
Critique: The tempting fix is adding `fetch`. The case then exercises the merge, but it still doesn't kill its row's mutant.
Consequences: The mutant has to be one that a merge separates from the merge base. Examples: the base is the pre-merge commit (`HEAD^1`), the base is the branch's fork point, or "sources added by commits in `origin/main@{before}..HEAD`".
Recommendation:
- Fetch before the merge.
- Assert the merge happened: the harvest contains `design-review-002 F1`, and `git log -1 --format=%P` has two parents.
- Name the mutant "the base is the commit before the merge (`HEAD^1`)", which reports the merged source as stale, and confirm the case kills it on the prototype.
Lesson: zz-test/no-vacuous-pass

### F5 [high] What `./zn commit`, `--uncovered` and `--stale` do with no `origin/main` is unspecified, and a promoted spec runs `./zn commit` with no remote
Where: Design, Rewrite ("The comparison base is `git merge-base HEAD origin/main`"; "`./zn commit` on a raft branch uses the same function"); Chore checklist Guards; `Overrides: none` (line 295)
Evidence:
- `z-nile/tests/acceptance/c0084/commit-phase.spec.luau` builds its fixture with a raw `git init` and "no remote, so start and done stay local" (its line 5). It runs `./zn commit -m work --issue <a> --time 2` on a started raft (line 143) and expects success.
- Under the Design, that commit computes `git merge-base HEAD origin/main`, which fails because the ref does not exist. The Design gives no outcome for that.
- If the executor follows zz-arch ("guards fail closed") and the Design's own stance ("does not parse is a failure, not a skip"), c0084 turns red, and no Override is named.
- If the guard skips instead, deleting `refs/remotes/origin/main` turns it off.
- The same question applies to `./zn lessons --stale` in `z-nile/check.sh` for every fixture that runs the gate. The ones that grep finds naming `z-nile/check.sh` are c0074 `done-gate`, c0114 `layout` and `gate-cover`, and c0120 `gate-homes`, `graph-homes`, `finished` and `promote-home`. It also applies in any checkout whose `origin/main` is missing.
- CI is fine: `check.yml` checks out with `fetch-depth: 0`.
Critique: The executor will pick a behaviour. One choice turns a promoted spec red with no Override named. The other leaves a guard that is off by default in offline repositories.
Consequences: A rule decided from text would be: "no `origin` remote" (`git remote` is empty) means a local repository, and the check is skipped with a warning. "`origin` exists but `origin/main` or the merge base does not resolve" fails closed. That rule needs both sides tested and has to be stated in all three callers.
Recommendation:
- State the rule above in the Rewrite section, for `./zn commit`, `--uncovered <id>` and `--stale` alike.
- Add cases: in a fixture with no remote, `./zn commit` succeeds and warns. In a fixture whose `origin/main` ref was deleted, `--stale` exits 1 and `./zn commit` refuses.
- Run c0084, c0001 and the gate-running promoted specs on the prototype, and record the result in E3.
- If a promoted spec still turns red, name it under `Overrides:`. As a chore this issue may carry its own.
Lesson: zz-test/pin-fail-safes-where-they-act, z-design/fallbacks-name-the-modes-they-cover

### F6 [high] `named-areas.spec.luau` is outside `acceptance/`, so it isn't sequestered, and it is listed as a Touched module the executor may edit
Where: `check.sh` AC3 (`"$HERE/named-areas.spec.luau"`); Touched modules line 247 (`z-nile/.tracker/issues/c0166/named-areas.spec.luau`); Maintainability; zz-test "Sequestered", "Where acceptance specs live"
Evidence:
- zz-test says "check.sh files and the acceptance specs they name are written in z-design … During execution they must not change".
- The code reviewer enforces that with `git diff … -- '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'`. A file beside `check.sh` is outside both globs.
- AC3's exact-rows half is the spec `named-areas.spec.luau` in the item folder. It is also listed under Touched modules, which tells the executor it is theirs to change.
- An executor whose `lesson-areas.md` disagrees with the `NAMED` table can edit `NAMED` until AC3 passes, and code mode's item 2 lists nothing.
Critique: Moving it into `acceptance/` gets it promoted (promotion takes every `*.spec.luau` there, `main.luau:3897`), which is what review 001 F10 wanted to avoid.
Consequences: The file needs a name that is sequestered but not promoted, and `tests/run` has to accept that name.
Recommendation:
- Move it to `acceptance/named-areas.luau` (not `*.spec.luau`, so it is not promoted, but under `acceptance/**`, so the sequestration diff sees it). Confirm on the prototype that `lune run tests/run -- "$A/named-areas.luau"` runs it, or have AC3 run it with `lune run` directly.
- Remove it from Touched modules.
- After `done`, `A` points at `tests/acceptance/c0166`, so AC3 must also say what it does when the file is absent there: skip with a message, or keep the file beside `check.sh` and accept that it stays sequestered.

### F7 [medium] Promoted specs still pin today's area table: the exact core set, and the live rows through the copied file (repeat of design-review-001 F10)
Where: `acceptance/parse-check.spec.luau` "the real tree lists every tag…" (`t.expect(sorted(parsed.core)).toEqual(sorted({ "process", "review", "scope", "sequestration" }))`); relevance, for-paths and prompt specs; Unknowns E1 ("Dropping `scope` and `sequestration` from core is not the fallback. Do not do it without the user.")
Evidence:
- parse-check is promoted, and it asserts the exact core set. E1 names changing core as a decision the user may take later. Taking it turns `z-nile/tests/acceptance/c0166/parse-check.spec.luau` red.
- relevance.spec has no table of its own, so (F1) it can only get one from the real file. Its expectations then depend on today's rows: `fence` maps to `z-nile/lib/fence.sh`, `tracker` to `z-nile/engine`, `acceptance` includes `@item`, and `review` is core.
- for-paths and prompt use `trackerfix.new(…, { noLessons = true })`. That clears `lessons/` folders but copies `z-nile/skills/lesson-areas.md` from the real checkout (`engine.copy` → `COPIED_SKILLS`), so they depend on today's rows for `fence`, `wiring` = `@skill`, and `review` core.
- If a later harvest maps `wiring` to a path, or moves `fence` to `z-nile/lib`, a promoted spec turns red.
- Review 001 F10's fix moved the explicit `NAMED` comparison out, but these specs still depend on the same rows.
Critique: The rule ("every tag has a key, every prefix is legal") was moved correctly, but the specs depend on the set in other ways.
Consequences: This interacts with F1. Once the table is an argument, the pure specs carry their own. The CLI fixtures seed their own `lesson-areas.md`, as they already seed their own lessons.
Recommendation:
- In parse-check, replace the exact-core assertion with "core is non-empty and every core tag has a key". The exact set already lives in the non-promoted named-areas check.
- Have relevance.spec build its table with `lessonareas.parse`.
- Have the for-paths, prompt, rewrite and rounds fixtures write their own `z-nile/skills/lesson-areas.md` in the seed.
- Check the result against zz-test/promoted-specs-pin-rules-not-sets.
Lesson: zz-test/promoted-specs-pin-rules-not-sets

### F8 [medium] "The skills it exercises" means the mode's skills only, so engine work loses zz-arch's lessons, c0166 included, and code-mode recall was never measured
Where: Design, Area table (mode lines); Unknowns E3; Problem (a) ("its Touched modules or diff paths, its project, the skills it exercises")
Evidence:
- I emulated `relevant`/`select` in `/tmp/c0166rev/emu.py`, using the Design's rows, the core set, the mode lines, `@item` and the project filter, with c0166's own Touched list plus its folder.
- `--for c0166 --mode design` keeps 106 of 124 design lessons. The 18 it drops are all zz-arch, out of 34. They include `zz-arch/one-reader-per-format` and `zz-arch/parsers-refuse-ambiguity`, the two lessons that apply to the new `lesson-areas.md` format and `lessonareas.parse` (F1, F9).
- Code mode drops 8 zz-arch lessons for the same issue.
- E3's three misses (`reorder-by-position`, `parsers-refuse-ambiguity`, `one-reader-per-format`) belong to the same class. These lessons are tagged `parsers`, `formats`, `drift`, `ordering` and similar, which map to `@skill`, so they reach only issues that edit `z-nile/skills/zz-arch`.
- AGENTS.md assigns skills by path: zz-arch is for "designing or writing the tooling: `z-nile/`…, `zn`, `scripts/`", pickman-arch is for "anything in `pickman/src/`".
- E3 replayed only `design-review` harvests. The new lesson `z-design/filter-proves-recall` says "and the code-review form for a build filter". In my replay of `review-NNN Fk` entries, only 2 come from items with repository-relative Touched lists, so code-mode recall is effectively unmeasured.
Critique: The tempting fix is the fallback E3 already rejected: add zz-arch to every design review. That keeps 123 of 129 on a maze review, which removes the filter.
Consequences:
- A path-to-skill map is a third kind of line in `lesson-areas.md` (for example `skill zz-arch: scripts, z-nile/affected.luau, z-nile/engine, z-nile/lib, z-nile/tests, zn`), and it needs the same legal-prefix rule.
- It must not use bare `z-nile`, or every z-nile item folder pulls zz-arch in.
- The maze count and E3 change, and a code-mode recall count needs either `--diff`'s paths or the project-relative items re-spelled for the count.
Recommendation:
- Add path-exercised skills, kept for any query path under their prefixes.
- Re-run E3 with them, and add a code-mode replay over the `review-NNN` entries. Where Touched lists are project-relative, prefix them with the project home for the count, and say that you did.
- Record both rates against the 90% bar, and the maze and fence counts.
- Add a relevance case: a z-nile engine path keeps a non-core zz-arch lesson tagged `parsers`, and a pickman Logic path does not.

### F9 [medium] The area file's parser has no rule for a repeated line or a tag spelled like a keyword, and no defined result when the file is missing or broken
Where: Design, Area table ("A line is `core: a, b`, or `mode <…>: skill, skill`, or `<tag>: <prefix>, <prefix>`… One tag per line"; "A prefix … not a legal `paths:` value is a parse error of the file")
Evidence:
- The Design does not say what `parse` does with two `fence:` lines, two `core:` lines, or two `mode design:` lines: keep the first, keep the last, merge, or refuse.
- Tags are free kebab words. A lesson tagged `core` needs a row `core: @skill`, and the parser reads that row as the core set.
- "A parse error of the file" has no consumer behaviour. The Design doesn't say what `--for`, `ready` (`buildLessons`), `--check`, `metrics` and `lessons` with no flags do when `lesson-areas.md` is missing (a fixture or tree without it) or does not parse: fail closed, no filter, or core only.
- No case covers any of this.
Critique: Without a stated rule, an implementation keeps the last duplicate silently, and a later harvest that adds a second `fence:` line changes what reviewers read with no error.
Consequences: Refusing duplicates means a harvest adding a prefix edits the existing line, which the zz-rules sentence should say. A reserved-word rule needs `--check` to name a lesson tagged `core` or `mode`.
Recommendation:
- `parse` returns problems for a repeated tag, `core` or `mode` line.
- `core` and `mode` are reserved tag words, and `--check` reports a lesson using them.
- A missing or unparseable file makes `--for`/`--paths` exit 1 naming the file, and makes `--check` report it. `buildLessons` then uses no filter and the ready command warns. State whichever choice you make in the Design.
- Add parse cases for each repeat and for the reserved word, and a for-paths case with the file removed.
Lesson: zz-arch/parsers-refuse-ambiguity, z-design/specify-every-named-artifact

### F10 [medium] Work in flight that the new checks fail when they land isn't named; only R0039 is
Where: Chore checklist, Existing work ("R0039 already has five design reviews…"); z-design 5.3, z-raft section 4 and zz-execute sentences ("Run ./zn lessons --rounds <id> and it must exit 0 before that commit")
Evidence:
- **Stale lessons on open branches.** For each `origin/prep-*` and `origin/R*` branch I listed the harvest lines added since its merge base whose lesson existed at the base with an unchanged `check:`:
  - prep-c0118: 39
  - prep-c0121: 19
  - prep-merge-past-tracker-only: 9
  - prep-sweeper-killed-under-load: 8
  - prep-paid-play-and-continues: 6
  - R0056-white-ghost-green-walls: 6
  - prep-colorful-cli-output: 5
  - R0059-frame-roundtrip-tolerance: 1
  
  After c0166 lands, each of these is red at `--stale` in the gate, and at `--uncovered <id>` (z-design 5.5, zz-execute Phase 4 step 5), for harvests made before the rule existed.
- **Loops already at 5 or more, without a note:**
  - R0044 (preparing, own loop at 5)
  - R0030 (prepared, 6)
  - R0040 (new, 5)
  - f0126 (13, member of prepared R0053)
  - c0117 (10, member of active R0052)
  
  `--rounds` exits 1 for each of these and for its raft. The skill sentences say `--rounds` "must exit 0 before that commit". R0044's next design round cannot satisfy that without a retroactive bullet and note, which the Design says nothing about.
Critique: The Design's answer for R0039 ("metrics prints `missing`; a later commit on some other raft is not refused") covers `./zn commit`. It does not cover `--rounds`, the skill sentences, or `--stale` on branches.
Consequences: Either these items get the note or rewrite, or the rules apply only to sources and rounds added after c0166's landing. The second needs a text anchor, such as the commit that first adds `lesson-areas.md`, which is decided from history, not from disk.
Recommendation: Name each item above under Existing work, and say what it does. Either:
- (a) its lead rewrites those checks, or writes the note, at its next harvest; or
- (b) `--stale` ignores harvest lines added before the first commit containing `z-nile/skills/lesson-areas.md`, and `--rounds`/the skill sentences apply only to a loop whose fifth review file was added after it.

Add a case for whichever is chosen.
Lesson: z-design/new-rules-migrate-existing-work

### F11 [medium] Several rules in the Design have no case, and the item-folder rule that E3's recall depends on is one of them
Where: Design, The command; Rules and mutants; `acceptance/for-paths.spec.luau`
Evidence: I checked each with `grep -n` over the seven specs:
- **`--for` adds the item's own folder to the query.** No for-paths fixture has an `@item`-tagged lesson (`acceptance`, `specs`, `check-sh`…). A `--for` that never adds the folder passes every case. relevance only tests `@item` on a path the test hands in. E3's 97.5% counts lessons kept through that folder.
- **`--mode`:** an invalid value exits 2, and a second `--mode` exits 2. Neither has a case.
- **`--mode code`, `raft` and `stream`** have no CLI case. In "a design mode keeps the exercised lesson the path would drop", `zz-execute/steps` is `when: build`, so `--when design` drops it whatever the mode. A `--mode` that keeps every skill passes the case.
- **Usage errors:** `--stale`, `--rounds` or `--uncovered` combined with `--for`, `--diff`, `--paths` or `--mode` should exit 2. Only `--check --for` is tested.
- **A bullet in the raft document** satisfies a member loop only when `<file>` contains the member's folder. Only the member-document arm has a case.
- **`--paths`** neither adds an item folder nor sets `exercised` without `--mode`. No case.
- **`--diff`, `--rounds` and `--stale` are booleans** and "do not consume the next word". No case (for example `lessons --stale --when build` exits 2 and does not treat `--when` as a value).
Critique: Each one can be dropped by an implementation while all seven specs stay green. The first one quietly undoes review 001 F1's fix.
Consequences: none.
Recommendation:
- Add an `acceptance`-tagged design lesson to the for-paths fixture, and a case where `--for c0001 --mode design` keeps it through c0001's folder while `--paths z-nile/lib/fence.sh` drops it.
- Add a design-phase zz-arch lesson that `--mode design` must drop.
- Add one case for each of the remaining usage errors.
- Add a raft-document bullet that satisfies a member loop, and one whose `<file>` names another member and does not.
- Add a Rules row for each.
Lesson: z-design/spec-design-correspondence, zz-test/kill-mutants-where-the-value-is-built

### F12 [low] The harvest's lesson edits restate this issue's findings as appended clauses
Where: `harvest.md`; the 14 edited lesson files (`git diff z-nile/skills`)
Evidence: Each harvested lesson gained a closing "And …" question about this issue in particular. Examples:
- no-check-red-between-steps: "And can the same commit add the area-table row a new tag needs before `lessons --check` runs?"
- instructions-runnable-where-they-run: "And is a new tag's area row a data file the harvest may edit, rather than an engine module the prep may not?"
- new-rules-migrate-existing-work: "And does a stored path that is not repository-relative get a named fallback…?"
- accepted-risks-checked-and-decided: "…when a captured word such as concrete…".

Another raft would not fail these the way it fails the lesson's rule. They are review 001's findings, restated. They also show how cheaply the new rewrite rule is met: appending a clause changes the `check:` line, and metrics then shows `since check 0`.
Critique: Checks grow by one issue-specific question per recurrence, which dilutes the question that catches the general defect.
Consequences: none for this issue's specs.
Recommendation: Rewrite each appended clause as the general rule it is an instance of, or fold it into the existing question. For example, `no-check-red-between-steps` already asks the general question, so drop the clause and put the c0166 example in the body under a **Note**.

### F13 [medium] A sequestered spec fails the gate's lint, so the prep's own gate is red
Where: `acceptance/rounds.spec.luau:227` ("a member's bullet": `local doc = fs.readFile(...)`)
Evidence: The stop hook ran `scripts/check.sh --affected` in this worktree, and selene reported ``rounds.spec.luau:228:9: warning[shadowing]: shadowing variable `doc` `` (twice; `0 errors, 2 warnings`), and the lint step `FAILED`. The local `doc` shadows the file-level helper `local function doc(id, slug, kind, extra)`. zz-test: acceptance specs are "formatted and linted" by the gate, so the prep commit lands a red gate, and the executor can't rename the variable in a sequestered spec.
Critique: The fix is a one-word rename (`text`), made in prep before the specs are sequestered.
Consequences: none.
Recommendation: Rename the local in rounds.spec. Run `scripts/check.sh --affected` (format and lint) on the prep tree before the next round, and record that it passed. The same run also reports a type error in `pickman/tests/acceptance/f0061/lobby-tooling.spec.luau(55,26)` (an invalid `%` pattern). That file is not part of this issue and isn't changed in this worktree: capture it as its own defect, don't fix it here.
Lesson: z-design/rerun-skipped-checks-after-edits

Candidate lesson (for the lead to harvest): z-design or zz-arch: when a design moves a table from code to a data file, every pure function that used the table gets it as an argument. Check: "Does every pure function that reads this table receive it from the caller, so that its spec can pass its own table?"

Verdict: changes
