# Proposed lessons from the c0173 and c0174 preps

For the lead to write under `z-nile/skills/<skill>/lessons/<slug>.md` (format: zz-rules, Items) and to name in harvest entries. Sources: c0173 and c0174 design reviews 001 to 005. The first entry sharpens an existing lesson (replace its `check` and append the paragraph); the others are new files.

## z-design/finished-overrides-land-before-ready
```
---
title: An edit to another item's sequestered file lands before the raft is readied
when: design
tags: [overrides, sequestration, process]
check: Does this design change, during execution, any other item's sequestered file (a `check.sh` or an acceptance spec, finished or not), not only a `done/…/check.sh` named on an Overrides line? Is that edit in this item's prep PR (or a tracker PR) on main before z-ready, and do zz-test's Sequestered section, zz-execute Phase 3 step 4 and its stream brief, zz-review Code item 2 and the prompt template each allow it, or only this issue's document?
---
(keep the existing body; append:)

c0173 and c0174 design review 001 (F1 and F4, high): two chores had to change a prepared item's sequestered spec (c0075's `wiring.spec`, c0083's `suites.spec`) after c0172 deleted the workflow they read. The first designs declared an execution-time "binding sequestration exception" in the issue's own document. No skill allows it: zz-test's one exception is a user-decided layout move for finished `check.sh` files, Phase 3 step 4 and code review item 2 list only `R100` renames, and the prompt template tells the executor "Never edit … an acceptance spec". A prep author cannot grant itself that hole. The user chose "in the prep commit"; the prep applied the reviewed patches and the execution became a verification-only raft.

**How to apply:** when the fix needs another item's sequestered file changed, put the question to the user at the first round (in the prep, as a reviewed patch; as a user-decided exception with the six places that forbid it rewritten; or inside the target's re-prep), and never write "the reviewer accepts this diff" into the issue.
```

## z-design/exact-checks-compare-against-the-merge-base
```
(append to the existing lesson; replace its check with:)
check: Does this check compare the tree with a fixed commit (the parent of a move, a sha in the design)? What does it say after main edits one of the files it judges, after an item finishes on main, after the branch lands and main moves on, and on a branch cut after the edit it checks has already landed on main (the prep carried it)? Can the author make the base equal HEAD, or make a judged file absent? Does a "merge base plus patch" comparison run `patch -N` or `-f` and also accept "the base already holds the patch, unchanged"?

(append this paragraph:)

c0173 and c0174 design review 002 (F1, high) and 003 (F1): a done-time check written as "file equals its merge-base text with the patch applied" went red for ever once the prep landed with the patch applied, because macOS `/usr/bin/patch` reverses an already-applied patch without asking (even with `-F 0`) and the compare then fails; a first version of the sequestration diff check also let a second file through because a bash regex's `.` crossed lines. A check that pins another item's file by blob or text also races that item's re-prep: no edit the branch may make turns it green afterwards.

**How to apply:** run each such check in a throwaway clone in four states (patch not yet on the base, patch on the base and the branch unchanged, the branch editing the file, main re-prepping the file), use `patch -N`/`-f` and a reverse dry run to tell "applied" from "unapplied", count lines instead of matching multi-line text with one regex, and pin a sequestered file by blob and mode.
```

## z-design/rederive-tolerances-from-the-decided-route
```
---
title: When a route is decided, every tolerance in the sequestered check is re-derived from it
when: design
tags: [check-sh, decisions, sequestration]
check: For each allowance in this check.sh (a file it may change, a state it accepts, a twin's file it waves through), which delivery route or option needed it, and does the route the user chose still need it? Can a branch pass by undoing another item's work under that allowance?
---
A sequestered check written while the route was open carries the permissions of every option. After the user picks one, the others' allowances stay in a file nobody may edit during execution, and they widen the check beyond the decision.

**Why:** c0174 design review 004 F1 (medium): AC4 still accepted "c0083's `suites.spec`, whatever its content" and c0173's file by blob, which only the execution-time route needed. With the prep route chosen, a branch could write the patched spec back over a re-prep that landed on main and pass all five criteria. The same review found route letters and "route (b)" comments left in `check.sh` after the decision (F2). The sequestered file cannot be fixed after the prep lands, so the clean-up has to happen in the prep.

**How to apply:** after each user decision, list every allowance in `check.sh` and in the Design with the option that needed it, delete those the chosen option does not need, rerun the clone states, and search the check and the Design for the dropped options' names ("route (b)", "tolerated").
```

## z-design/experiments-assert-on-the-assertions-subject
```
---
title: An experiment that justifies a change asserts on the same subject as the case it judges
when: design
tags: [experiments, evidence]
check: Does the experiment's question quote the exact assertion it is about (which value, which spec, which input), and would it come out differently if that assertion were still correct?
---
**Why:** c0174 design review 001 F1 (high): E3 claimed the old real-folder example no longer killed the "changed folder matches only tokens above it" mutant because c0172's `deploy.spec` names the folder. The case asserts that c0001's `ci-workflow` is selected, which only the inside-folder rule selects, so the mutant still failed it. The experiment had looked at which specs the folder selects instead of whether the asserted spec is still selected. The wrong conclusion justified a rewrite of another item's reviewed criterion and a false sentence in its document.

**How to apply:** copy the assertion into the experiment's question, run the mutant, and record the assertion's own result before deciding that a case needs changing.
```

## z-design/pins-name-who-reprep-goes-first
```
---
title: A chore that pins another item's file names, where its re-prep author reads it, who re-preps the chore if the re-prep goes first
when: design
tags: [reprep, ordering, sequestration]
check: If the target item is re-prepped between this prep and this item's `done`, can any edit the executor may make turn this item's checks green, and who has been told, in a document the re-prep's author reads (not only this issue's)?
---
**Why:** c0173 design review 003 F1 and c0174 design review 003 F2: both chores pin the exact text of items whose re-prep (promised by c0114 and c0120) is still owed. If the re-prep lands first, the blob pin and the exact-text checks fail by construction, nothing retires an issue but `./zn done`, and the chores' own documents are never read by the re-prep's author.

**How to apply:** write the ordering duty into the patched target documents themselves ("a re-prep started before cNNNN is done also re-preps cNNNN, its patches and pins rewritten, or makes it a member of the raft"), pin that sentence in the chore's check, and make the escalation signal explicit (the check's refusal message).
```

## zz-review/lists-paste-their-search
```
(note to add to the existing lesson, sources: c0173 design review 003 F3, c0174 design review 003 F1 and 004 F3)

A list of "all the places" that was typed by hand missed lines twice in c0174 (c0083.md lines 272, 273 and 281) even after a review asked for the search; paste the search command and its output, grouped by what each hit needs, and take the line numbers from that output.
```

## z-design/checks-read-only-what-the-branch-cannot-rewrite
```
---
title: A sequestered check proves nothing through files the branch can rewrite
when: design
tags: [check-sh, sequestration, experiments]
check: For each file this check.sh reads or runs (an item's `experiments/` patches or harnesses, another item's document), is it sequestered, pinned by blob, read from the merge base, or covered by an unchanged-from-base check?
---
**Why:** c0174 design review 005 F1 (medium): AC3 compared c0083.md with its merge-base text plus `experiments/c0083-doc.patch`, and AC2 ran `experiments/folder-case.luau`. Neither file is sequestered, so an execution could edit the document, regenerate the patch to match, or gut the harness, and pass 5 of 5 while the sequestration diff of the reviewer saw nothing. It is the same mechanism as the tolerance for an unchosen route (z-design/rederive-tolerances-from-the-decided-route).

**How to apply:** list every input of the check, and put each input the branch should not change under an unchanged-from-merge-base check (a glob pathspec that survives the move to `active/` and `done/`), or pin it by blob; then run the clone state "edit the judged file and regenerate its patch".
```
