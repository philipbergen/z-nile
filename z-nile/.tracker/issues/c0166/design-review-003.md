# Review 003: c0166 (design mode)
Inputs: prep worktree `prep-relevant-review-lessons` at 53de68b4 plus its uncommitted working tree: `c0166.md`, `check.sh`, `acceptance/` (7 `*.spec.luau` and `named-areas.luau`), `harvest.md`, `design-review-001.md`, `design-refute-001.md`, `design-review-002.md`, `design-refute-002.md`, the 21 edited lesson files and the new `z-design/lessons/filter-proves-recall.md` and `zz-arch/lessons/table-reaches-pure-functions.md`. origin/main is now 4e9aef1a. Since the base it changed lessons only (two new lessons with the new tags `order`, `workstreams` and `ranges`, plus body edits). Nothing under `z-nile/engine`, `z-nile/tests/lib`, `z-nile/templates`, `z-nile/check.sh` or `scripts` changed (`git diff --stat HEAD origin/main -- …`).
Ran: `./zn capture c0166` (3e349d10, no marker). Problem and Solution are unchanged from the capture. `lune run z-nile/affected -- <path>` for each of the 13 engine, skill, template and gate Touched paths printed `ALL` every time. `grep -rlF -e <path>` over `z-nile/tests/acceptance` and `pickman/tests/acceptance` for each path and basename. `./zn lessons --skill zz-review --full`. `--for` is an unknown option in this worktree's engine (`unknown option --for`), so I ran `./zn lessons --when design --full` (131 lessons) and asked each check. `./zn lessons --check` printed ok (139). `./zn lessons --uncovered c0166` reported every finding covered. `selene` and `stylua --check` on `acceptance/` were clean. A Python scan of every lesson's `check:` found none under 4 words and none equal to its title. Read: `main.luau` (`recordAndCommit`, `cmd.commit`, `cmd.lessons` `--uncovered`, `withPromotedCopies`, `done`'s promotion), `lessons.luau` (`sources`, `uncovered`), `tests/lib/trackerfix.luau`, `tests/lib/engine.luau` (`copy`, `clearLessons`, `COPIED_SKILLS`), `tests/run.luau`, `z-nile/check.sh`, promoted c0116 `issue-design`, c0120 `gate-homes`, c0114 `gate-cover`, and the 12 skills' Lessons sections.
Scratch, outside the repository: `/tmp/c0166r3`, a shell replay of `engine.copy`'s skills copy followed by `clearLessons` (F2).

Dropped from design-review-002: F1, F2, F3, F4, F5, F6, F7, F8, F10 and F11 (each fix is in the text and the specs), F9 (the parse rules and the `--for` missing-file case are in; the callers it left without a case are F8 here), F13 (the locals are renamed, and selene reports 0 warnings). F2's last bullet (build the prototype of this text before round 3) was not done. F1 and F2 below are two more sequestered cases that fail an implementation that follows the Design, which is what that bullet was for. F12 is repeated as F12.

### F1 [high] The five-round harvest note is a later source of an existing lesson, so `./zn commit` refuses both crossing commits that rounds.spec requires to pass
Where: `acceptance/rounds.spec.luau:189` ("fifth design round noted") and `:211` ("fifth code round noted"); Design, Rewrite ("A source is what `lessons.sources` already records, plus `from:` as one source"), Five rounds ("The ids must be lesson ids that exist"); Rules rows "a later source with an unchanged check is refused" and "a note that names a missing lesson does not satisfy the loop"
Evidence:
- `lessons.sources` (lessons.luau:268–295) records note entries as sources (`{e.item} note {e.note}`). The live tree shows it: `recommendations-pick-spec-or-check` lists `c0137 note design review 003's candidate lesson` among its sources.
- In rounds.spec the lesson `zz-test/pin` is seeded with `from: user 2026-10-26: said so`, so its first source is on the base.
- "fifth design round noted" stages `harvest.md` = `- note 5 design rounds, design prompt unclear: zz-test/pin` on branch `R0001-lessons` and does not touch pin's `check:`. For that note, `staleSource(notOnBase = true, afterCheck = true, firstSource = false)` is true, so the Design's `./zn commit` refuses with `commit: zz-test/pin gained a source and its check line did not change`. The case requires exit 0. "fifth code round noted" (`CODE_NOTE` naming `zz-test/pin` on `R0005-code`) fails the same way.
- The Design requires the note's ids to be lessons that exist. So every satisfying note is a later source of an existing lesson, and the two mechanisms collide on every crossing commit, not only in this fixture.
- The case "a missing lesson id" asserts only `missing.code == 1`. Under the Design that commit is refused by the stale rule whatever the id check does, so in the CLI the Rules row's mutant ("any id is accepted") lives. Only the pure case (lines 63–66) kills it.
- This is the fourth hole in the source and rewrite mechanism: review 001 F6 and F7, review 002 F3, now this. Every one was in a row added as `reasoned` and never run.
Critique: The executor can't satisfy rounds.spec and the Design together. The tempting fix is to exempt `- note 5 …` lines from `sources`. That makes the five-round lesson the one lesson whose recurrence is never measured, which is the opposite of Problem (d) "harvested as a lesson for that step" together with (b) "an ineffective one is rewritten".
Consequences: If the crossing commit must also sharpen the named lesson's check:
- the five-round sentences (z-design 5.3, z-raft 4, zz-execute Phase 4 step 3) gain "and changes that lesson's check line, or names a new lesson";
- naming a lesson created in the same commit has to stay legal (its first source is the note, so it is not stale);
- the `--rounds` path in a prep has no `./zn commit`, so `--uncovered` and `--stale` catch it there, as for any source.
Recommendation:
- Decide in the Design that a five-round note is an ordinary source, so the crossing commit changes each named lesson's check or names a new lesson. Write that into the three five-round sentences, and pin it in briefs.spec beside "including when the verdict is approve".
- rounds.spec: in "fifth design round noted" and "fifth code round noted", change pin's `check:` in the same commit. Add a case where the note is in the commit, the check is unchanged, and the commit is refused with the `gained a source` message. In "a missing lesson id", assert the rounds message, not only the exit code.
- The mechanism: build the prototype of this text and run all seven specs, `named-areas.luau` and every `reasoned` mutant on it before round 4. Record each result in E2. The Unknowns already promise this ("The next prototype runs …"). Three rounds of `reasoned` rows have each produced specs that contradict the Design.
Lesson: z-design/prove-specs-pass-on-a-prototype, z-design/spec-design-correspondence

### F2 [high] "a source from before the area file" can't pass: every trackerfix fixture is seeded with the real `lesson-areas.md`, and one Design sentence makes the grandfather rule say the opposite
Where: `acceptance/rewrite.spec.luau:227–255`; Design, Rewrite ("A source … is in force only when the commit that added it has `z-nile/skills/lesson-areas.md` in its tree. … When `origin/main` does not contain the file, nothing is grandfathered, so a fixture that seeds the file exercises the rule and a fixture that omits it shows the exemption."); `tests/lib/engine.luau:47,78–82,88–98`
Evidence:
- `trackerfix.new` always runs `engine.copy`. That copies `engine.COPIED_SKILLS = { "z-nile/skills" }` whole (`cp -R`). `clearLessons` then removes only each `<skill>/lessons` folder. Step 1 creates `z-nile/skills/lesson-areas.md` at execution, so every fixture's seed commit contains it, including this one, which seeds no area file.
- Replayed in `/tmp/c0166r3`: after `cp -R top/z-nile/skills dest/z-nile/skills` and the `clearLessons` loop, `find dest -type f` printed `dest/z-nile/skills/lesson-areas.md`.
- So the commit "harvest before the file" has the file in its tree. That puts its source in force, and the early `lessons --stale` exits 1 with `gained a source`. The case requires exit 0.
- The quoted Design sentences also conflict with each other. "When `origin/main` does not contain the file, nothing is grandfathered" makes every source in force in exactly the fixture that "shows the exemption", while the per-commit sentence exempts it. The spec follows the per-commit sentence.
- Removing the file from `engine.copy` is not open to the executor. The Design says the promoted c0111 lessons-cli and c0115 lessons fixtures "run `./zn lessons --check` against this table", so they depend on the copied file.
Critique: The executor can't edit the spec, and the only engine-side escape breaks two promoted specs. The tempting Design fix (delete the "nothing is grandfathered" sentence) still leaves the case red.
Consequences: The case has to build the history that today's main really has: an origin/main without the file, then a commit that adds it. It must show that the file is absent before the first harvest (zz-test/no-vacuous-pass).
Recommendation:
- In the Design, keep one rule: a source or fifth review file is in force exactly when the commit that added it has the file in its tree. Delete the `origin/main` sentence, or replace it with what it was meant to say.
- State in the Design that `engine.copy` seeds every fixture with the real `lesson-areas.md`, which c0111 and c0115 rely on.
- Rewrite the case:
  - `git rm` the copied file and commit, push that commit to the fixture's origin, and assert `git ls-tree origin/main z-nile/skills/lesson-areas.md` is empty;
  - then commit the first harvest (`--stale` exits 0), add the file (commit), add the second harvest, and expect exit 1.
- Run it on the prototype (F1).
Lesson: z-design/prove-specs-pass-on-a-prototype, zz-test/no-vacuous-pass

### F3 [high] `named-areas.luau` does not check "today's exact rows": an extra tag row or skill line passes it
Where: `acceptance/named-areas.luau:115–131`; AC3 ("Today's exact rows are checked by `acceptance/named-areas.luau`"); Design, Area table ("A tag that is not in the named rows below maps to exactly `{ "@skill" }`. … A key whose prefixes are not `@skill` and that is not in the named table is not [allowed]"); Unknowns E1 (`state` is deliberately not mapped)
Evidence:
- The check walks `for tag, prefixes in NAMED` and then the three named `@skill` keys. It never looks at any other key of `parsed.areas`, and it reads only the `zz-arch`, `pickman-arch` and `pickman-test` entries of `parsed.skills`.
- A `lesson-areas.md` with an extra `state: pickman/src/shared/Logic` row passes it. That is the mapping E1 rejected because it "pulled tooling lessons into maze reviews". So does an extra `skill zz-test: z-nile/tests` line.
- The promoted parse-check case accepts both, because each prefix is legal. The rule the Design states ("not in the named table" means `@skill` only) has no check anywhere.
Critique: AC3 can be passed by a table with wrong rows, and such a row silently changes which lessons every review reads.
Consequences: A rule that every other key is exactly `{ "@skill" }` is today's text. So it belongs in the unpromoted file, not in a promoted spec (zz-review/recommendations-pick-spec-or-check). A harvest that adds a named row later changes the table, and that is fine: the file is not in the gate.
Recommendation:
- In `named-areas.luau`, assert that every key of `parsed.areas` not in `NAMED` equals `{ "@skill" }`.
- Assert that the keys of `parsed.skills` are exactly `pickman-arch`, `pickman-test` and `zz-arch`, and the keys of `parsed.exercised` exactly the four modes.
- Mutant: the `state` row above. It must turn AC3 red.

### F4 [medium] Where `./zn lessons --stale` goes in `z-nile/check.sh` is unspecified, and one placement turns a promoted spec red
Where: Design, Chore checklist Guards ("`z-nile/check.sh` gains one line, `./zn lessons --stale`"); Implementation step 5; `z-nile/check.sh:96–110` (`--plan` exits after the fence refusals); `z-nile/tests/acceptance/c0120/gate-homes.spec.luau:224–231`
Evidence:
- gate-homes "--plan writes nothing" runs the gate with stub tools on `PATH`. The stub `lune` appends to `calls.log` for any call except `--version` and `z-nile/roots`. The case asserts `fs.isFile(calls.log) == false`.
- `./zn` ends in `exec lune run z-nile/engine/main -- "$@"`. If the line sits anywhere before `if [[ -n $plan ]]`, `--plan` logs a call and the promoted spec turns red.
- The Design also doesn't say:
  - whether `--plan` prints a line for this stage ("print what each stage reads");
  - whether `--project pickman` (that is, `pickman/check.sh`) runs it. Pickman's lessons go through the same check;
  - whether it runs in `--affected` as well as `--full`.
- The c0120 and c0114 gate specs that grep found (`gate-homes`, `graph-homes`, `gate-cover`, `finished`, `layout`, `promote-home`) are not among the Regression guard's named specs. They are covered only by "every promoted spec … that run[s] `commit` or `metrics`", which these don't.
Critique: An executor who puts the line near the top, as a "static stage", turns c0120 red, with `Overrides: none`.
Consequences: Running it after the plan exit and in every mode keeps `--plan` side-effect free. Running it whatever `--project` says makes a pickman-only gate check z-nile's lessons too. That is right, because lessons live under both projects' skills. The plan output then needs a line for it, or a sentence saying it has none.
Recommendation:
- In the Design: the line runs after the `--plan` exit, in both modes, whatever `--project` says, as its own `stage "lessons: stale sources"`. `--plan` prints `lessons: stale sources against origin/main`, or the Design says it prints nothing for it.
- Add c0120 `gate-homes`, `graph-homes`, `promote-home` and c0114 `gate-cover` to the Regression guard. Run them on the prototype.

### F5 [medium] The rewrite rule is restated in only two places. Every other path that adds a note to an existing lesson now hits a refusal it is not told about
Where: Design, Skill sentences (the rewrite sentence goes only into z-design 5.3 and zz-execute Phase 4 step 5); the Lessons sections of the skills
Evidence: `grep -rn "adds a note to an existing lesson\|note ws-<issue>\|first harvest anything" z-nile/skills/*/SKILL.md` prints:
- `z-raft:61`, `z-run:20`, `z-ready:30`, `z-design:92`, `z-ticket:33`, `zz-arch:43`, `zz-execute:150`, `z-stop:24`, `zz-rules:187`, `zz-stats:31`, `zz-test:134`, `zz-review:110`. That is the same Lessons-section sentence in 12 skills: "It adds a note to an existing lesson when one fits … and commits both with its work".
- `zz-execute:46`: Phase 2B writes stream candidates as `- note ws-<issue>: <lesson ids>` and commits them with `./zn commit -m "<issue>: lessons"`. Under the Design that commit is refused unless each named existing lesson's check changes.
- `zz-execute:102` (Phase 5 step 3) and `z-design:73` (step 5.5): "first harvest anything `--uncovered` still lists".

None of these gets the sentence. The Phase 2B commit is a `./zn commit`, so a lead who follows zz-execute line 46 is refused, and no instruction says why.
Critique: The rule is enforced on every path and taught on two (z-design/restated-rules-move-together, z-design/required-steps-on-every-path).
Consequences: A shared sentence in 12 Lessons sections is one rule restated 12 times. The rule should live once, in zz-rules Items (the ledger format's owner), with each place referring to it. The five-round note (F1) is the same rule.
Recommendation:
- State the rule once in zz-rules (Items, the harvest ledger): "a later source of an existing lesson changes that lesson's check line in the same commit; `./zn commit`, `--uncovered` and `--stale` refuse otherwise".
- Add "(zz-rules: a later source changes the check)" to the shared Lessons-section sentence, to zz-execute Phase 2B line 46, and to z-design 5.5 and zz-execute Phase 5 step 3.
- Pin it in briefs.spec as a rule, not a set: every `z-nile/skills/*/SKILL.md` that contains `adds a note to an existing lesson` also contains that reference, and zz-rules contains the sentence.

### F6 [medium] "the lesson's first source" and "added after the commit that last changed `check:`" have no defined order
Where: Design, Selection (`staleSource(notOnBase, afterCheck, firstSource)`, `recurred`), Rewrite ("it is not the lesson's first source"; "added after the commit that last changed the lesson's `check:` line"); `lessons.sources` (lessons.luau:268–295)
Evidence:
- **First.** `lessons.sources` returns each lesson's sources in item-id order (`byId(items)`), reviews before notes. It does not return them in time order. The Design never says which source is "first" when the lesson has no `from:`.
  - Take lesson L, introduced by R0062's harvest (its only source). Later, c0050's prep, still open, adds a source with L's check unchanged.
  - Read as list order, c0050 is first, so `firstSource = true` and the recurrence is never stale. R0062's source is on the base. Nothing is reported.
  - Read as time order, c0050's source is stale.
- **After.** A raft branch merges origin/main as zz-execute requires. A source added on the branch and a check change made on main are then unordered by ancestry, though ordered by date.
  - Ancestry: not after, so not stale.
  - Author or commit date: after, so stale.
  - The same split applies to `since check` in metrics.
- No case covers either reading. Every rewrite.spec lesson has `from:`, and no case has a check change on main side.
Critique: Two implementations that both follow the text disagree on what the gate's `--stale` reports (z-design/one-reading-per-value). This is the same mechanism as F1.
Consequences: Picking ancestry needs a rule for concurrent commits. Picking date trusts a timestamp the author writes. That trust is weaker, but it is only a nudge toward rewriting, not a security guard.
Recommendation:
- Define "first source" as the `from:` line when it is present; otherwise the source whose line was added by the earliest commit (`git log --reverse` on the ledger lines, ancestry first, then commit date).
- Define "after" as "the source's commit is a descendant of the check's commit (`git merge-base --is-ancestor`), or the source is in the index".
- Add two cases:
  - a lesson with no `from:`, first harvested by a higher item id, then a lower id; the lower id's source is stale;
  - a check change merged in from main, concurrent with a branch source; whichever answer you pick.
- Add a Rules row for each.

### F7 [medium] The area table is read from the branch under review, so a harvest can narrow its own reviewers' lessons and the gate stays green
Where: Design, Area table ("A harvest may edit this file"), The command (`--for` reads `z-nile/skills/lesson-areas.md` from the working tree), Maintainability (the exact rows are not in the gate); promoted parse-check "the real tree" (requires only a non-empty core whose tags have keys)
Evidence:
- A prep's design reviewer runs `--for <id> --mode design` in the prep worktree, which reads that worktree's table.
- A harvest edit that drops `sequestration` from `core:`, or moves `fence` to a path the issue doesn't touch, passes the promoted rule. The rule needs only a non-empty core with keys and legal prefixes. `named-areas.luau` runs only in c0166's own `check.sh`. So that prep's reviewers and its ready prompt read fewer lessons, and nothing in the gate notices.
- zz-arch/guards-trust-only-origin: configuration that widens or narrows a check is read from origin/main, never from the tree a branch edits.
Critique: The table decides which `check`s a review asks, which makes it a review guard. Today any branch can loosen it for itself.
Consequences:
- Reading only origin/main breaks the same-commit new-tag rule: the new tag has no key there until the branch lands.
- A union fixes that: keys, prefixes, core tags and mode skills from both origin/main and the working tree. A branch can then widen the filter but not narrow it.
- `--check` still validates the working tree's file.
- No origin, or no origin/main: the working tree alone, with a warning, like `--diff`.
Recommendation:
- `--for` and `buildLessons` select with the union of origin/main's table and the working tree's.
- Add a for-paths case: the fixture's working-tree table drops `review` from `core:`, and `--for` still keeps `zz-review/core`.
- Add a Rules row: "a branch's table can widen, never narrow".

### F8 [medium] The missing or unparseable area-file fail-safe is pinned only at `--for` with the file missing
Where: AC3 ("A missing or unparseable area file makes `--for` and `--paths` exit 1 and `--check` report it, and `buildLessons` applies no path filter"); Design, The command; `acceptance/for-paths.spec.luau:179` (the only case); Rules row "a missing area file makes `--for` exit 1"
Evidence: `grep -n "lesson-areas.md is missing\|does not parse\|no path filter" acceptance/*.luau` turns up:
- one `--for` case with the file removed;
- the `no Touched modules` and `not repository-relative` warnings.

Nothing covers:
- `--paths` with the file missing;
- either command with a file that does not parse, such as `core: review\ncore: process\n`;
- `--check` reporting `lesson-areas.md is missing` or `does not parse`;
- `ready` (`buildLessons`) keeping every build lesson and warning `warning: lesson-areas.md is missing; no path filter`.

An implementation where `--check` ignores a missing file, `--paths` filters to core, or `buildLessons` crashes passes all seven specs.
Critique: The fail-safe is stated for four callers and pinned at one (zz-test/pin-fail-safes-where-they-act).
Consequences: none beyond the cases.
Recommendation:
- In for-paths: `--paths` with the file missing exits 1. `--for` with a repeated `core:` line exits 1 with `does not parse`. `lessons --check` reports both states.
- In prompt.spec: a `ready` with the file removed from the seed (`git rm` it after `trackerfix.new`, because of F2) keeps `zz-stats/tally` and warns.
- A Rules row for each.

### F9 [medium] Escalate to the user: E3 measures only recall, so whether outcome (a) gets smaller reviews is never decided
Where: Problem (a) and the paragraph before it ("each review pays to read them all, most have nothing to do with what the issue touches, and the checks that do apply are diluted"); Unknowns E1 (the size condition retired), E3 ("c0166's own design query then keeps 124 of 124 … That is the cost of outcome (a)"; "A maze design review keeps 99 of 130")
Evidence:
- E3's pass bar is recall of at least 90 percent, and a filter that keeps everything meets it.
- E1 retired the size condition and put nothing in its place.
- By the design's own counts:
  - a tooling issue like this one keeps every design lesson (124 of 124);
  - a maze design review keeps 76 percent (99 of 130);
  - a maze raft review keeps 92 of 130.
- `z-nile/skills` is both a `skill zz-arch` prefix and the area of `docs`, `documents`, `skills`, `renames`, `migration` and `stale-text`. So every issue that edits any skill keeps all of zz-arch and those tags.
- "Reads only the relevant lessons" now holds through the author's reading of "relevant", and the user's stated cost ("pays to read them all") is unchanged for tooling work.
Critique: Trading recall for size is a scope decision about a captured outcome. The Design records it as the author's ("That is the cost of outcome (a)"). It carries no `Decided with the user` line (z-design/accepted-risks-checked-and-decided: "when a captured word has a weaker reading … is the stronger reading the one the check enforces unless the user chose the weaker one?").
Consequences: Any size bar changes E3's fallback ("add the missed skill to that mode's exercised line"), because each added skill raises the size.
Recommendation: escalate to the user, with the numbers above:
- (a) accept recall first: record `Decided with the user (date)` with the tooling, maze-design and maze-raft counts;
- (b) add a size bar beside the recall bar, for example a maze design review at most N of 130 and a skill-only edit at most M. Then tune `z-nile/skills` out of the `skill zz-arch` line and measure both bars in E3. The cost: more misses, so a lower recall that the user has to accept.
Don't pick either without the user.

### F10 [low] Two Rules rows name the wrong mutant or the wrong case
Where: Rules and mutants rows "a later source with an unchanged check is refused" and "a note that names a missing lesson does not satisfy the loop"
Evidence:
- The first row's mutant, "`staleSource` is false when the source is not after the check", is the correct behaviour, not a mutant. Its case, `rewrite :: needsRewrite and laterCount`, is the pure case, while the end-to-end refusal is `rewrite :: second source`.
- The second row names `rounds :: crossing`, whose missing-id commit asserts only the exit code. That commit is refused for another reason (F1), so the CLI half doesn't kill "any id is accepted".
Critique: An auditor who runs the named mutant can't make it fail, and the table claims coverage that case doesn't give.
Consequences: none.
Recommendation:
- First row: mutant "`staleSource` ignores `afterCheck`" (or "… `firstSource`"), on case `second source`.
- Second row: name the pure case (`promptFailure and needsPromptNote`, the `badNote` assertion) and the CLI case once F1 makes it assert the message.

### F11 [low] `scripts/…` Touched paths are "not repository-relative", and `--paths` with no item has no project filter
Where: Design, The command ("A path is repository-relative when its first segment is a project name in `projects.toml` … or a root-level file the area table names (`AGENTS.md`, `zn`)"); `skill zz-arch:` prefixes (`scripts`); "The project filter is `buildLessons`'s test: … `projectOfRoot(item.root)`"
Evidence:
- `scripts` is a zz-arch prefix but a root-level folder. Read literally ("file"), an item touching `scripts/check.sh` or `.github/workflows/check.yml` falls back to every lesson, with a warning.
- Read loosely ("a root-level entry the table names"), `scripts` filters.
- With `--paths` and no `--for` there is no `item.root`, so it is unspecified whether `pickman-play/feel` is kept for `--paths z-nile/lib/fence.sh`. for-paths asserts neither way.
Critique: These are two small one-reading gaps. Both fail open (more lessons), so this is low.
Consequences: none.
Recommendation:
- Say "a root-level file or folder the area table names", or list `scripts` explicitly.
- Say `--paths` without `--for` keeps every project's lessons, or only those of the project the command runs in (`ZN_CWD`).
- Add a for-paths assertion for whichever you pick.

### F12 [low] Appended check clauses still restate this issue's findings, and the rewrite rule rewards appending (repeat of design-review-002 F12)
Where: the edited lessons' `check:` lines (`git diff z-nile/skills | grep '^[-+]check:'`); refute 002 F12 ("the appended questions that named this issue's artifacts are the general rule")
Evidence:
- `zz-test/pin-fail-safes-where-they-act`: "And is each of a failed diff, a path that matches nothing, and an unparseable lesson pinned at the command that decides". Those are c0166's three fail-safes.
- `z-design/never-narrow-captured-scope`: "And does a selector still return every class the capture says that reader sees, including the skills that step exercises?" That is this issue's selector.
- `z-design/rerun-skipped-checks-after-edits`: "And was the lint run on the specs after the last edit that could shadow a name?" That is review 002 F13's `doc` shadowing.
- Every one of the 21 rewrites appends a clause, and none replaces one. The longest checks are now 162 words (`design-the-execution-window`, 5 questions) and 139 (`prove-specs-pass-on-a-prototype`). The median is 38.
- Under c0166's own rule, appending "And …?" is the cheapest way to make `since check` 0. So checks grow by one question per recurrence, which is the dilution the Problem complains about.
Critique: The new rule measures "the check line changed", not "the check got sharper".
Consequences: Bounding check length would be a new rule with its own migration. Leave it as a zz-stats observation unless the user wants more.
Recommendation:
- Fold each clause above into the existing question, or move the c0166 example into the body under **Why**.
- Add one sentence to zz-stats' interpret step: a check over about 100 words, or with more than 3 questions, is a candidate for a rewrite chore. That is a report, not a refusal.

Candidate lesson (for the lead to harvest), z-design: when two new rules read the same record (here, harvest lines read both as sources and as five-round notes), run a case where one commit satisfies both. Check: "Does any commit a new rule requires also trip another new rule that reads the same lines?"

Verdict: changes
