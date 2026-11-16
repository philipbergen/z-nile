# Backfill worker brief (c0112)

You are a worker in the lessons backfill of the pickman repository (`<REPO>` below is the checkout the lead names). You read review findings that were written before every finding had to name the step that erred, and you write the harvest lines and lesson drafts that the rules now ask for. You change nothing in the repository: you write only under your batch folder `<OUT>`, which the lead names.

## Hard rules
- Read the repository; write **only** under `<OUT>/` (the folders `harvest/` and `lessons/`, and the files `when-change.txt` and `report.md`). Never edit a file in the repository, never run `git` to change anything, never run `./zn new`, `./zn commit` or any command that publishes, and never write a lesson file under a `skills/*/lessons/` folder: your lesson drafts go in `<OUT>/lessons/`, and the lead places them.
- You are a subagent: you do not decide scope. Every finding in your batch gets a line. You never drop a finding, merge two findings into one line, or skip a low one.
- Do not edit or "fix" a review or refute file. They are history.
- Every command you start outside the checks below ends on its own (use short reads, no servers, no watchers).

## What the rule is (c0136, summarized; the skills hold the full text)
A **step** is a skill. For each finding ask two questions: *which step made this mistake?* and *which earlier step should have prevented or caught it?*
- `erred <skill>`: the skill whose instructions the author was following when the mistake was made: `z-ticket` (a vague or wrong capture), `z-design` (a design hole, an under-specified criterion, a prep slip), `z-raft` (a bad grouping or raft design), `z-ready` (a wrong prompt), `zz-execute` (a build mistake), `zz-review` (a reviewer's own mistake, or a wrong earlier-round recommendation), or a skill the author read for the work: `zz-test` (a spec or `check.sh`), `zz-arch` (the tooling's code), `pickman-arch` or `pickman-test` (the game's code and specs), `zz-rules` (tracker and git procedure). **Never the step under review by default**: a code review that finds a design hole names `z-design`; a design review that finds a vague capture names `z-ticket`. Every finding of a design-phase review (a `design-review-NNN`) is a mistake design made or should have caught: name `z-design`, `z-ticket`, `z-raft` as `erred`, or, when the rule broken belongs to a skill the author read (`zz-test` for a spec, `zz-arch` or `pickman-arch` for code), name that skill as `erred` and add `upstream z-design`. Prefer `erred z-design` when the defect is the design process itself (a missing Rules row, a stale document, an unrun experiment) and the topic skill when the defect is a violation of that skill's own rule. `erred zz-review` is only for an earlier round's own wrong finding or recommendation. `erred none` is only for a finding that points out no mistake (a taste call, a disagreement with no mistake on either side, a clarity note), and then the line is a one-off; a finding that points out a mistake too specific for a lesson is also a one-off but names the step that made it.
- `upstream <skill>` (optional): an earlier step's skill that should have prevented or caught the same mistake. It is never the same skill as `erred`.
- Use the **current** skill names. Old reviews use the old ones: make-issue = `z-ticket`, ticket-prep = `z-design`, ready-raft = `z-ready`, launch-raft = `z-run`, execute-raft = `zz-execute`, stop-raft = `z-stop`, review = `zz-review`, tracker = `zz-rules`, metrics = `zz-stats`, testing = `zz-test`, architecture = the game's rules `pickman-arch` (or the tooling's `zz-arch`). When the text of a mistake came from one step and a later step reworded it, name the step that first wrote the wrong text. Work that predates any skill: name the skill whose rules would have prevented it today.

**A lesson is filed under its `erred` skill or its `upstream` skill, and only those** (`./zn lessons --check` refuses any other filing). A lesson is `when: design` or `both`, never `build`, when its line names a design step (`z-ticket`, `z-design`, `z-raft`) or answers a finding of a design review (`design-review-NNN`), except a lesson filed under `zz-review` for a reviewer's own mistake.

## Harvest line forms (one line per finding, in the file's order)
```
- design-review-001 F1 (erred z-design): z-design/a
- design-review-001 F2 (erred z-design, upstream z-ticket): z-ticket/b, z-design/a
- review-001 F4 (erred none): one-off: <the reason, one sentence>      (no mistake in the finding)
- review-001 F5 (erred z-design): one-off: <the reason, one sentence>   (a mistake too specific to repeat)
- stream-review-c0010-001 F1 (erred zz-execute): zz-test/c        (zz-test is the lesson's skill, so the line must name it: erred zz-test, or upstream zz-test)
- note <what happened, one sentence> (erred zz-test): zz-test/c
- note design-review-001 F2 <a spec rule too> (erred zz-test): zz-test/c       (a further lesson of a finding)
```
- `upstream <skill>` does not require a lesson filed under that skill; a lesson, when there is one, is filed under `erred` or `upstream`. A lesson whose skill is neither is refused.
- A line names at most two skills (`erred`, `upstream`). Its lessons are filed under those two skills only: at most one lesson per skill is the normal case, a second under the same skill is fine.
- A finding whose lessons span a **third** skill keeps the third lesson as a source in a note headed `<review stem> F<n>`, with its own group naming the lesson's skill: `- note design-review-001 F2 also a spec rule (erred zz-test): zz-test/c`. A note headed for a finding must name a review that exists and a finding it has. A note that is not about a finding must not contain a word shaped like `F2` or a first word containing `review-`: write "finding 2", not "F2".
- A **one-off** (`: one-off: <reason>`) is a finding with no lesson: either it points out no mistake at all (a taste call, a disagreement that holds no mistake on either side), which is `(erred none)`, or it points out a mistake too specific for another raft to repeat (a typo, a number or name specific to that one item), which still names the step that made it: `(erred z-design): one-off: <reason>`. A step that missed a point in one design is a mistake another design can make: that is a lesson, not a one-off. A one-off is the exception, not the way out of a hard finding: if a different item could fail the same way, it is a lesson. The reason says why in one sentence.
- Existing lines already in an item's `harvest.md` keep their finding key and **every lesson id they name** (a lesson id may move to a note about the finding only when the rule above forces it); you add the group, and you may add further lessons. An existing note keeps its text and gets a group. A line's lesson ids are separated by `, `.
- The `# Harvest: <item>` heading stays as it is (a ledger that has none gets none). A review whose verdict says there are no findings has no `### F<n>` heading and gets no line; a `## Judged criteria` item (`JC1`) is not a finding.

## Choosing lessons
1. `<OUT>/../lesson-index.txt` lists every existing lesson: `id | when | tags | title`. Read the lesson file when a title is close (the path is `<skills folder>/<skill>/lessons/<slug>.md`; the real folders are `z-nile/skills/` and `pickman/skills/`).
2. **Reuse an existing lesson when the finding repeats its rule.** More sources for a lesson is the point. Do not write a near-duplicate.
3. **Otherwise draft a new lesson** (see below) when the finding names a defect a different item could repeat. Several findings of your batch that share one defect share one draft.
4. If the only existing lesson that fits is filed under a skill that is neither `erred` nor `upstream`, either name that skill as `upstream` when it is an earlier step or a skill the author read for it, or draft the lesson under the skill that erred and keep the old one as a note's source (`- note <stem> F<n> ... (erred <its skill>): <old id>`).

## Reading a finding
A review is `design-review-NNN.md` or `review-NNN.md` (or `stream-review-<issue>-NNN.md`, or `focused-review-NNN.md` once c0136 has landed) beside its refute file (`design-refute-NNN.md`, `refute-NNN.md`, `stream-refute-<issue>-NNN.md`). The refute tells you how the finding was resolved: `fixed` (the finding was right and something changed), `refuted` (the author rebutted it, and then it is one of two things: a reviewer's mistake another reviewer could repeat, such as an unrun claim or a misread spec, which is `(erred zz-review)` with a `zz-review` lesson; or a taste call or disagreement with no mistake, which is a one-off `(erred none)`; if the refuted finding still names a repeatable mistake of the author's, treat it as valid), or answered some other way. A `### F<n>` heading is a finding. A refute that defers a finding (to a later issue) or accepts it in part still answers a valid finding: it is a lesson, not a one-off. Findings repeat across rounds: a repeat is the same mistake again and takes the same lessons, and its `erred` is the step that made the mistake the first time.
Read the finding's `Where`, `Evidence`, `Critique` and `Recommendation`, not only its title: the title is often the symptom.

## New lesson drafts (`<OUT>/lessons/<skill>--<slug>.md`)
A complete lesson file in the final format, named `<skill>--<slug>.md` (the lead places it at `<skills folder>/<skill>/lessons/<slug>.md`, and the lesson id is `<skill>/<slug>`):
```
---
title: <a rule, not a symptom: "A new rule says how existing work gets through it">
when: design | build | both
tags: [a, b]
check: <one question, ending in ?, that an author asks of a draft or of code to catch this defect>
---
<The rule in one or two sentences.>

**Why:** <the item and finding it came from: "R0010 design review 2 (F3): <what happened>">.

**How to apply:** <what to do, concretely.>
```
- The `check:` line is one line ending in `?`.
- Slug and tags: lowercase kebab. Reuse the existing tags (`<OUT>/../lesson-index.txt` shows each lesson's) before inventing one. The slug is unique among the existing ids and among your drafts.
- `when`: `design` when the author could catch it while designing, `build` when only writing code can show it, `both` otherwise. Follow the rule above for design steps and design reviews.
- It must be a lesson a **different** raft could fail, written as a rule, not a restated finding. The `check` question must be answerable from a draft or a diff. Do not write the lesson for a game-specific number or name.
- If a finding would sharpen an existing lesson (a new case for its `check`), do not draft a copy: list it in `report.md` under `sharpen`, with the lesson id and the sentence to add.
- If an existing lesson's `when:` is wrong for a finding you attribute (it is `build` and your line names a design step, or answers a design review's finding), write `<lesson id> <design|both>` on a line of `<OUT>/when-change.txt`. The validator applies it to its scratch copy so that you can reach `ok`, and the lead applies the same file to the real lesson.

## Output
`<OUT>/items.txt` lists your batch's items (the lead wrote it). Write a `harvest/<item>.md` for every one of them and for no other: the validator refuses an extra or a missing file.
Per item of your batch, `<OUT>/harvest/<item>.md`: the **complete** new `harvest.md` for that item (heading, every finding of every review file of the item as one line, in review then finding order, then the item's notes in their old order). The lead copies it over the item's `harvest.md`. Then `<OUT>/lessons/` (the drafts), `<OUT>/when-change.txt` (when needed) and `<OUT>/report.md` with these sections, each possibly empty: `unsure` (findings where the step or the lesson was a judgment call: item, review, finding, one sentence), `sharpen`, `refuted` (findings the author refuted, and what you made of each), and `counts` (lines written, one-offs, drafts).

## Check your work before you finish
Run `bash <CHECK> <REPO> <OUT>` (the lead gives the path of `backfill-check.sh`). It copies the tree to a scratch folder, overlays your files, and runs `./zn lessons --check`, `--uncovered` and `--unattributed` for your items, and compares the sources every existing lesson had. Fix every problem it prints, rerun, and end only when it prints `ok`. Then your final message is a short summary: the counts and the `unsure` list.

## If c0181 has landed
(The lead fills this section from c0181's landed text, or deletes it if `grep -- --policy z-nile/engine/main.luau` finds nothing.) A draft carries the state key c0181 requires, written as: <the key and its allowed values>. Two lessons that `./zn lessons --check --policy` reports as similar are merged or marked `distinct_from` as c0181 says: <the form>. The validator runs `--check --policy` for you.

## Audit mode (the lead says so in your task)
You are given the `one-off` lines of your items instead of whole items. Write the same outputs (`harvest/<item>.md` is still the complete new `harvest.md` of each item), but change only the `one-off` lines you think another item could repeat: give them a step and lessons (existing or drafts). Leave every other line as it is. The validator checks you like any worker.
