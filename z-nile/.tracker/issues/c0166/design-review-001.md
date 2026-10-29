# Review 001: c0166 (design mode)
Inputs: prep worktree `prep-relevant-review-lessons` at 53de68b4 plus its uncommitted `z-nile/.tracker/issues/c0166/{c0166.md,check.sh,acceptance/*.spec.luau}` (7 specs); `./zn capture c0166` (3e349d10, no marker); `lune run z-nile/affected -- <path>` for each engine, skill and template Touched path (all print `ALL`) and `grep -rlF -e <path> z-nile/tests/acceptance pickman/tests/acceptance`; `./zn lessons --skill zz-review --full`; `./zn lessons --when design --full` (129 lessons; `--for` is an unknown option in this worktree's engine: `unknown option --for`, so the unfiltered list was used); c0117's sequestered specs in `z-nile/.tracker/issues/active/c0117/acceptance/`; `z-nile/engine/main.luau` (`touchedModules`, `buildLessons`, `cmd.commit`, `raftDesignRounds`), `z-nile/engine/lessons.luau` (`sources`); the live tracker (Touched lists, harvest ledgers, review files). The prototype was reverted, so nothing was run against it. Only reads and shell counts ran; no file other than this one was written.

### F1 [high] The selector drops the lessons of the skills a review exercises, and E1 measured how few lessons are left, not whether the right ones are
Where: Design, Selection (`relevant` rules 1–3) and Area table; Problem (a); Unknowns E1
Evidence: Problem (a) says the reviewer reads lessons relevant to "its Touched modules or diff paths, its project, **the skills it exercises**". The Design selects only by path. A skill folder counts only when a Touched path is inside it (rule 3), so z-design's lessons reach a design review only when the issue edits `z-nile/skills/z-design`. Take a pickman maze design whose Touched list is `pickman/src/shared/Logic/Maze` and `pickman/tests/unit/Maze` (plus its prep specs under `pickman/.tracker/issues/<id>/acceptance`). Reading the tags of the 38 z-design lessons against the table, these are dropped from that review:
- `z-design/spec-design-correspondence` (`[acceptance, rules-and-mutants]`): `acceptance` maps to `*/tests/acceptance` and does not overlap the prep spec folder; `rules-and-mutants` is `@skill`.
- `z-design/specify-every-named-artifact` (`[completeness, executability]`, both `@skill`).
- `z-design/decided-guesses-rewrite-their-body` (`documents` → skills folders).
- `z-design/check-open-defects-on-the-path`, `z-design/late-pins-run-on-the-merged-deps-tree`, `z-design/design-the-execution-window`, `z-design/exact-checks-compare-against-the-merge-base`, `z-design/one-reading-per-value`, `z-design/readings-from-text-not-disk`, `z-design/restated-rules-move-together`.
- `zz-review/recommendations-pick-spec-or-check` and `zz-test/fixed-lines-run-their-whole-criterion` (`check-sh` → `z-nile/lib/ac.sh`). Every design writes a check.sh, but these only reach issues that edit `ac.sh`.
- In raft mode, `zz-review/claims-cite-a-prototype-holding-the-files` (`[rafts, prototypes, evidence]`, `rafts` → `z-nile/engine`) is dropped from every pickman raft's coherence review, which is the only review it is about.

These are checks on the design document and its specs. They apply to every design, whatever code it touches. E1's pass condition is "a maze review reads about a third of the design lessons". A selector that keeps a random third would also pass it. Nothing measured recall.
Critique: The fix an author will reach for is adding `rules-and-mutants`, `completeness` and the like to `CORE`. That's one tag at a time, and it grows a core that E1 already calls too large ("the core of 26").
Consequences: When "the skills a review exercises" becomes an input, each mode needs a defined skill set. Design mode needs at least z-design, zz-review and zz-test. Raft mode needs z-raft and zz-review. Code and stream mode need zz-execute, zz-review and zz-test. The count rises, and E1's numbers change. The item's own artifacts (its document, `check.sh`, `acceptance/`) also need to be a query path, or `acceptance`, `check-sh` and `specs` lessons never match a prep.
Recommendation: Model "the skills it exercises" explicitly. Each mode gets a skill set whose lessons are always kept for that phase (an `EXERCISED` map in `lessonareas` keyed by `design`/`raft`/`code`/`stream`, or a `--mode` flag the briefs pass). Add the item's own folder to the query paths, and map `acceptance`, `check-sh`, `specs` and `mutants` to it too. Replace E1's count criterion with a recall experiment over data the repo already has: for every harvested `design-review-NNN Fk: <lesson ids>` entry in an issue's `harvest.md`, would `--for <that issue>` have selected that lesson? State a pass bar, for example ≥ 90% of harvested lessons selected, and a fallback if it fails. Add spec cases: a design-mode query on a pickman path keeps a non-core z-design lesson; a build-mode query keeps a non-core zz-execute lesson; an `acceptance`-tagged lesson matches an item whose only spec path is its `.tracker/issues/<id>/acceptance` folder.
Lesson: z-design/never-narrow-captured-scope

### F2 [high] Putting `--for <id>` "inside the same backticks" turns c0117's dispatcher specs red, but Overrides says none
Where: Design, Skill sentences, last bullet ("gains ` --for <id>` inside the same backticks… Do not remove the substring `` `./zn lessons --when design --full` ``"); Chore checklist "Existing work"; `Overrides: none`
Evidence: c0117's specs pin the command together with its closing backtick: `dispatch.spec.luau:166` `has(p, "`./zn lessons --when design --full`")`, `:183` and `:194` the same for `--when build --full`, and `dispatch-cli.spec.luau:238`. The bullet tells the executor to write `` `./zn lessons --when design --full --for <id>` ``. That text does not contain `` `./zn lessons --when design --full` ``, because the closing backtick now comes after `<id>`. So the bullet's two instructions contradict each other. The Chore checklist's claim that "a longer command that still contains that substring stays green" is false for the backticked substring. c0117 is `active` in R0052. If R0052 lands before c0166 executes, `dispatch.luau` exists, its specs are promoted to `z-nile/tests/acceptance/c0117/`, and following the bullet turns four assertions red with no Override named.
Critique: The tempting fix is "append `--for <id>` after the closing backtick". That splits one command across two code spans, and a headless model may run only the first, unfiltered one.
Consequences: The dispatcher arm depends on landing order. Whichever arm the design picks needs its spec impact named.
Recommendation: Pick one, and say it in the design:
- (a) If `dispatch.luau` exists at execution, name `z-nile/tests/acceptance/c0117/dispatch.spec.luau` and `dispatch-cli.spec.luau` under Overrides. As a chore this issue may carry its own override. Use the narrowing rules (zz-test/narrowing-pins-the-whole-file): the four `has` lines widen to the backtick-free substring, and the rest of the file stays pinned.
- (b) Keep c0117's backticked string as it is, and add a second, separate sentence naming the filtered command, with an explicit instruction to run the filtered one.

In both cases, reword the Chore checklist sentence so it states which substring c0117 pins, backticks included.
Lesson: z-design/run-the-other-rafts-specs

### F3 [high] Live prepared items name Touched paths relative to the project home, so `--for` and the ready prompt silently cut them to the core lessons
Where: Design, The command (`--for` paths come from `touchedModules`); Chore checklist "Existing work"; AC2, AC7
Evidence: The area table and overlap rule use repository-relative prefixes (`pickman/src/...`). Live items in flight do not:
- R0057 (`prepared`, member c0150): `tests/acceptance/f0104/keys.spec.luau`, `.tracker/issues/done/f0104/f0104.md`, …
- R0053 (`prepared`, member f0126): `src/shared/Logic/Picks`, `src/shared/Logic/Maze/init.luau`, …
- R0044 (`preparing`, member d0124): `src/shared/Logic/Hiscores/init.luau`, `src/server/HiscoreStore.luau`, …

None of these overlaps any row or skill folder. The list is non-empty, so the "no Touched modules" warning does not fire. `--for R0053`, and the ready prompt `buildLessons` writes for R0053, therefore hold only core lessons, with no warning. `z-design/touched-paths-exist` already says these lists should be repository-relative. Nothing enforces that, and the design neither migrates these items nor detects them.
Critique: The tempting fix is to re-spell those three items. That fixes today's tree, but the next project-relative path is silently filtered again.
Consequences: A detection rule has to decide what counts as a path that matches nothing. If it is decided from disk, `z-design/readings-from-text-not-disk` applies: an item's own new file doesn't exist yet. If it is decided from text, the rule needs the registry's project homes.
Recommendation: Decide unmatched paths from text. A Touched path whose first segment is neither a registered project home (from `projects.toml`) nor a root-level file the table names is reported: `warning: <id> Touched path <p> is not repository-relative; no path filter`. That item falls back to nil paths, the same as an empty list. `buildLessons` uses the same rule. Add a for-paths case (`src/shared/Logic/Maze` warns and keeps every build lesson) and a prompt case. Under Existing work, name R0057, R0053 and R0044 and say what each does: re-spelled in its own folder before c0166 lands, or covered by the fallback.
Lesson: z-design/new-rules-migrate-existing-work

### F4 [high] A raft's design-round count adds up its members' independent preps, so rafts where no review loop reached 5 are reported as prompt failures
Where: Design, Rewrite, five rounds, metrics ("Design rounds… are the counts metrics already prints: `raftDesignRounds`"); `--rounds`; z-raft section 4 sentence; AC5
Evidence: `raftDesignRounds` (main.luau:5184) adds the design-review files of the raft folder and of every member. On today's tree:
- R0061: members c0134 = 4, c0135 = 3, c0137 = 4. The sum is 11, but no loop reached 5.
- R0062: members c0139 = 4, c0141 = 4, plus 1 raft round. The sum is 9, with no loop at 5.

Under the design, metrics lists both as `missing`, and `./zn lessons --rounds R0062` exits 1. z-raft's new sentence says `--rounds <R-id>` must exit 0 before the commit of the raft's review file. So the next coherence review of any raft whose members sum to 4 or more forces a "Prompt failure" bullet saying a prompt "was unclear", even though no review loop went past 4. The user's words are "When we hit 5 rounds", which means one loop. Problem (d)'s report would then be mostly false positives, which defeats its point.
Critique: The tempting fix is "count only the raft folder". That drops a member whose own prep reached 5, the case (d) is about.
Consequences: A per-loop count needs to know which loop each file belongs to: each issue's folder in prep, the raft folder in raft mode, and code rounds. A re-prep that resets scope restarts the count (z-design step 5.4), and that rule would need to come along.
Recommendation: Count rounds per review loop: each member's own design rounds, the raft's own design rounds, and the raft's code rounds. A raft is listed, and `--rounds` exits 1, when any one loop is at 5 or more without a bullet naming that loop. The bullet's `at <file>` names the loop's folder. Add rounds-spec cases: a raft with members at 4 and 4 and no raft rounds is not listed and exits 0; a raft with one member at 5 and no bullet on it is listed `missing`; a member's bullet satisfies its own loop. The design's "or, for design, in a member document" rule is untested today (F8).

### F5 [high] AC4 never asserts the "check unchanged" state, so metrics hard-coded to "check rewritten" passes
Where: AC4; `acceptance/rewrite.spec.luau` "metrics lists the recurrence as rewritten"; Rules and mutants (no row)
Evidence: The only metrics assertion is `has(r.stdout, "zz-test/pin: later 1, check rewritten")`. No case produces a lesson with a later source and an unchanged check, and none asserts `check unchanged`. If metrics printed `check rewritten` for every lesson, or skipped the `intro ~= head` comparison, the whole spec would still pass. "Ineffective means later > 0 and unchanged" is the Problem (b) measure, and it is the one output nothing checks. The ordering rule ("most later first, then id") has no case either.
Critique: The spec can't reach the unchanged state through `./zn commit`, because the new refusal blocks it. The author may decide the state can't happen and leave it untested. It can happen: plain `git commit` in streams and preps (F6), and every lesson already on the tree.
Consequences: none beyond the case.
Recommendation: In rewrite.spec, seed a second lesson with its first source, then add a later harvest line by plain `fixture.git` commit, bypassing `./zn commit` the way a prep does. Assert `later 1, check unchanged` and that it sorts before a `later 1` lesson with a greater id and after a `later 2` one. Add a Rules row: "rewritten compares the introducing commit's check with HEAD | rewrite :: metrics unchanged | always print rewritten".

### F6 [high] The rewrite-on-recurrence refusal lives only in `./zn commit` on raft branches, which misses most harvests, while z-design's new sentence promises it
Where: Design, Rewrite (`./zn commit`… refuses); Skill sentences, z-design step 5.3 ("./zn commit refuses the commit when the check line did not change"); Problem (b) "an ineffective one is rewritten"
Evidence:
- `cmd.commit` calls `recordAndCommit(activeRaft(), …)`, and the design itself says "Prep worktrees are not on a raft branch, so `./zn commit` is not available there". z-design commits with plain git (step 6).
- Harvest entries on today's tree: 450 in issue ledgers (prep) and 345 in raft ledgers. So most later sources are made where nothing refuses, and the z-design sentence the briefs spec pins (`same commit changes that lesson's check line`) describes a refusal that never runs there.
- Streams commit with plain `git commit` (zz-execute Phase 2B).
- zz-execute Phase 5 step 2 merges origin/main and commits with `./zn commit --phase deliver`. When that merge is concluded through `./zn commit`, main's prep harvests (never refused) are staged against HEAD, and the raft is refused for lessons it never touched.
- No gate check exists, so a PR that breaks the rule passes CI.
Critique: The tempting fix is a new "the prep lead must rewrite" sentence in z-design. That's an instruction with no check, which is the gap this issue exists to close.
Consequences: Moving the rule into a check needs a reference for "already had a source". `zz-review/sequestration-reference-not-a-ref` and `z-design/exact-checks-compare-against-the-merge-base` both apply: judge the branch's own delta against `git merge-base HEAD origin/main`, never against HEAD alone. That also makes main's own harvests arriving by merge harmless.
Recommendation: Make the rule a check over the branch's delta from the merge base, run where every path already stops:
- `./zn lessons --uncovered <id>` (z-design step 5.5, zz-execute Phase 4 step 5 and Phase 5 step 3 all require it to pass), or `lessons --check` when given an id.

Keep the `./zn commit` refusal only if it uses the same function and the same base. Rewrite the z-design 5.3 sentence to name the command that actually refuses. Add cases:
- a prep-style plain commit adding a later source is reported by `--uncovered <id>`;
- a merge of a main that carries someone else's later source is not reported;
- a check line changed on the branch clears it.

Lessons: z-design/required-steps-on-every-path, zz-arch/refusals-are-gate-checks

### F7 [medium] "Rewritten" means the check differs from the one the lesson was created with, so a lesson that keeps recurring after its rewrite still reads as handled
Where: Design, Rewrite, five rounds, metrics ("`rewritten` means the `check:` at HEAD differs from the `check:` in the first commit"); Problem (b) "it is measured whether a lesson stops its defect from recurring"
Evidence: Take a lesson rewritten after its second source that then gains five more. Metrics prints `later 6, check rewritten`, the same row shape as a lesson rewritten once that never recurred again. Once the refusal is in force, every later source made through `./zn commit` changes the check, so every post-landing lesson becomes "rewritten". The report can then no longer tell an effective lesson from one whose rewrites keep failing. Problem (b) asks whether the lesson stops its defect from recurring, which means recurrence after the current check.
Critique: The tempting fix is adding a "times rewritten" column. That counts edits, not whether the latest edit worked.
Consequences: This needs the commit that last changed the `check:` line, which costs one `git log -L`/pickaxe lookup per lesson that has a later source. The Scalability section bounds that already. Sources are ordered by review id, not by date, so "since" needs the commit that added each harvest line.
Recommendation: Report `later <n>, since check <m>`: m counts sources whose harvest line was added after the commit that last changed the lesson's `check:` line. A lesson with m > 0 has recurred since its current check and is the one to rewrite, and zz-stats' sentence says so. Add a rewrite-spec case: a check is rewritten, then gains one more source by plain commit, and the row shows `since check 1`.

### F8 [medium] Behavioural rules in the Design with no spec case and no Rules row
Where: Rules and mutants; Design "Guards" bullet, The command, Rewrite
Evidence: The specs were searched (`grep -n "does not parse\|unchanged\|later first\|member\|--rounds" acceptance/*.luau`). None of the following has a case:
- **Fail-closed parse refusal** "`commit: <id> does not parse`". The Chore checklist calls it the guard that "fails closed", and no spec stages an unparseable lesson. Mutant: skip unparseable files.
- **The member-document bullet** "or, for design, in a member document" for `--rounds` and metrics. Every fixture raft in rounds.spec has `issues: []`. Mutant: read only the raft document.
- **A raft's `--rounds` including member rounds.** Untested for the same reason. Interacts with F4.
- **`--diff` succeeding with no Touched modules** ("If they did not, `paths` stays nil and the empty warning also applies", and the success arm with no Touched list). Mutant: `--diff` paths discarded when Touched is nil.
- **`--paths` with zero arguments is a usage error.**
- **Recurrence ordering** (F5).

Critique: Each is a sentence in the Design that a wrong implementation can drop with all seven specs still green.
Consequences: none.
Recommendation: Add one case and one Rules row for each of the rules above, in the spec named in the Test plan for its AC. Mark each row `run` once mutated on the next prototype.
Lessons: z-design/spec-design-correspondence, zz-test/pin-fail-safes-where-they-act

### F9 [medium] The concrete-check rule ("check repeats the title") flags nothing on today's tree and accepts `Is it?`
Where: Design, Area table paragraph ("A word-count rule for 'concrete' was rejected… The concrete-check rule is the existing 'one line ending in `?`' plus this title rule"); Problem (b) "actionable (each has a concrete check question)"; AC3
Evidence: Over all 137 lesson files, no check equals its title. The shortest check has 16 words (`zz-arch/locks-detect-change`). So the new rule rejects nothing that exists, and a future `check: Is it?` passes `--check`. The design rejected a stronger rule because c0115's `lessons.spec.luau` runs `./zn lessons --check` on `Pinned?`/`Fair?` fixtures. That is a reason to name an Override (this issue is a chore and may), not a reason to weaken what (b) asks for. No `Decided with the user` line records the weaker reading.
Critique: The tempting fix is a word count. A count alone is a proxy too ("Is the thing right in every case?" passes it).
Consequences: Any rule that applies to folder-bearing trees changes c0115's promoted fixture. The design has to name that file as an Override, narrowed whole (zz-test/narrowing-pins-the-whole-file), or keep the rule to the real tree.
Recommendation: escalate to the user: options are:
- (a) Keep the title rule as the whole meaning of "concrete" and record that as `Decided with the user`.
- (b) Add a rule that applies only when `tree.folders ~= nil`, for example at least N words and naming at least one thing (a backticked term, a path or a noun phrase beyond pronouns). This costs an Override of `z-nile/tests/acceptance/c0115/lessons.spec.luau`, whose fixture checks get longer, plus refusal cases on both sides of the bound (zz-test/refusals-tested-on-both-sides).
- (c) Have reviewers judge each new lesson's check in item 10 (already "judge the lessons the author added"), and state that as the mechanism.

### F10 [medium] The promoted parse-check spec pins today's whole area table, so changing any area later turns a promoted spec red
Where: `acceptance/parse-check.spec.luau` "the real tree lists every tag and has no scope problem" (the `NAMED` table and `NAMED[tag] or { SKILL }`); Design, Maintainability ("A new area is a prefix in that key")
Evidence: The case loads the real lesson tree and requires, for every tag, `sorted(AREAS[tag]) == NAMED[tag] or { "@skill" }`, and every non-NAMED key to be `@skill`. After promotion, each of these turns `z-nile/tests/acceptance/c0166/parse-check.spec.luau` red, and so needs an Override chore:
- a new lesson tagged `maze` mapped to `pickman/src/shared/Logic/Maze`;
- an added prefix on `specs`;
- the F1 or F3 fixes.

The Maintainability section says the opposite. The rule it means to pin ("every tag on the tree has a key; a key outside the named set is `@skill`") holds only while the named set is frozen.
Critique: The tempting fix is to drop the real-tree case. That loses the "every tag on the tree has a key" rule, which is the reachability outcome the capture's Solution asks for.
Consequences: Today's exact rows are a claim about today's text, so they belong in a non-promoted check. The reachability rule stays a spec.
Recommendation: Keep in the spec only the rules: every tag on the real tree has an `AREAS` key, every prefix is a legal `paths:` value or `@skill`, and `--check` on the real tree is `{}`. Move the exact `NAMED` comparison to a `check.sh` criterion of this issue, which runs at its check and at `done` and never again.
Lessons: zz-test/promoted-specs-pin-rules-not-sets, zz-review/recommendations-pick-spec-or-check

### F11 [medium] A lesson with a new tag turns `lessons --check` red in the harvest step, and the only fix is an engine edit no skill tells the lead to make
Where: Design, Area table ("a tag with no key is a `--check` problem"), Maintainability; Skill sentences (z-design 5.3, zz-execute Phase 4 step 5, zz-rules Lessons bullet)
Evidence: z-design step 5.3 and zz-execute Phase 4 step 5 require `./zn lessons --check` right after writing new lessons. A prep that harvests a lesson tagged with a word not in `AREAS` gets `unlisted tag <t>`. The only fix is editing `z-nile/engine/lessonareas.luau`, which is code in an engine module, inside another issue's prep PR, outside its Touched modules. The listed skill sentences don't say whether that is allowed, or that the lead should pick an existing tag instead. In practice leads will re-tag to pass, and the lesson then lands under an area that doesn't fit.
Critique: The tempting fix is to say "pick an existing tag", which makes the vocabulary frozen without anyone deciding that.
Consequences: Allowing the edit means the zz-rules item rules and the "no code without a tracker issue" rule need an explicit exemption for `lessonareas.luau` in a harvest. The alternative is moving the table out of engine code into a data file that lives with the lessons (one reader, `lessons.load`).
Recommendation: Choose one and write it into the zz-rules Lessons bullet and the two harvest sentences:
- (a) the table is a data file beside the skills (for example `z-nile/skills/lesson-areas.md`), parsed by `lessons.load`, which a harvest edits like a lesson;
- (b) a harvest may add an `@skill` key to `lessonareas.luau`, and only that, with the rule stated.

Pin the chosen sentence in briefs.spec.
Lessons: z-design/instructions-runnable-where-they-run, z-design/no-check-red-between-steps

### F12 [medium] The 5-round harvest note that traces the failure to a step is only prose: the bullet alone passes every check
Where: Solution "harvested as a lesson for that step"; Design ("The harvest line, in the same commit, is `- note 5 <design|code> rounds, …: <lesson ids>`"); AC5; rounds.spec "crossing"
Evidence: In rounds.spec, `commit("fifth design round noted")` succeeds with the bullet added and no harvest line. Neither `needsPromptNote` nor `--rounds` reads `harvest.md`. `--uncovered` covers review findings, not notes. So the captured outcome "harvested as a lesson for that step" has no Checked criterion, and an implementation that ignores the note passes.
Critique: The tempting fix is to require any `- note 5 …` line. That can name no lesson, or an id that doesn't exist.
Consequences: The check needs the note's lesson ids to resolve to lessons that exist. Under c0136's quoted rule they should also be filed under the step the bullet names (capture → z-ticket, design → z-design, ready → z-ready). That mapping is a new rule and needs its own row.
Recommendation: Have `needsPromptNote`/`--rounds` also require, in the same document's item ledger, a `- note 5 <kind> rounds, <step> prompt unclear: <ids>` line whose ids all parse as existing lessons, with `<step>` equal to the bullet's. Add cases: bullet without note → refused; note naming a missing lesson → refused; matching pair → allowed.

### F13 [low] The Design says the commit loads "each staged lesson file", but the spec requires a refusal when only harvest.md is staged
Where: Design, Rewrite ("loads each staged lesson file against `HEAD`"); rewrite.spec "second source"
Evidence: In "second source" only `harvest.md` is written and staged. `pin.md` is unchanged, and the case expects `commit: zz-test/pin gained a source…`. An executor following the Design's sentence iterates staged lesson files, finds none, and passes the commit, then has to work out the real rule from a failing spec.
Critique: Executability: the Design and the spec state different rules.
Consequences: none.
Recommendation: State the rule as the spec has it: for every lesson id whose source count in the index's ledgers exceeds its count at the base and whose base count was > 0, the check line must differ between base and index. This merges with F6's base.

### F14 [low] The prototype ran only seven named regression specs, although `affected` prints `ALL` and other promoted specs drive the changed commands
Where: Unknowns E2; Regression guard
Evidence: `lune run z-nile/affected --` prints `ALL` for every engine, skill and template path. `grep -rlE '\{ *"commit", *"-m"'` finds 10 promoted specs that run `./zn commit`, which gains two refusals: c0001, c0008, c0038, c0045, c0053, c0067, c0074, c0080, c0084, c0120. `grep -rlE '"metrics"'` finds 9 that run metrics, which gains two sections: c0043, c0045, c0053, c0084, c0111, c0114, c0115, c0116 ×2. E2 reports only "the promoted regression specs named in the Regression guard passed". The design leaves the full gate to the executor, where a red promoted spec "stops the raft".
Critique: Running the full gate only at execution moves a prep-time finding into the raft.
Consequences: none.
Recommendation: On the next prototype, run `z-nile/check.sh --full`, record the result in E2, and add any spec that drives `commit` or `metrics` to the Regression guard.
Lesson: z-design/prove-specs-pass-on-a-prototype

Candidate lesson (for the lead to harvest): zz-review or z-design: a selector or filter design proves recall, not just reduction. Its experiment replays past harvested findings and counts how many of their lessons the filter would have shown. Check: "Would this filter have shown each past reviewer the lessons their findings were later harvested into?"

Verdict: changes
