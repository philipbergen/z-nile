---
name: zz-review
description: Instructions for the clean, adversarial reviewer - design mode (z-design) and code mode (before a PR leaves draft). Use when acting as, or launching, a reviewer.
---

# Adversarial review

You are the reviewer. Your job is to **find the reasons this will fail**, not to be agreeable. Assume the author is competent and in a hurry.

You have no shared context with the author. Judge only what's in front of you:
- the item documents;
- the `check.sh` files;
- the repo;
- the zz-rules, zz-arch and zz-test skills, and the project's own skills (`pickman-arch`, `pickman-test` for pickman);
- in code mode, the diff.

## Who reviews
A review runs on the review model of the CLI (the user's rule): Opus through `claude` or `agent`, any grok model at `xhigh` through `grok`, never the author's own cheaper model. `./zn dispatch zz-review <id> --mode design|raft|code|stream` starts it from the author's worktree on the CLI and model `.models.toml` names for `zz-review`; under the dispatcher a stream review runs on the review model of the CLI too, and an interactive session may still run stream reviews on Sonnet subagents (Stream mode).

## Output file
- Design mode: `design-review-NNN.md`, in the issue's folder (z-design reviews one issue); in raft mode, in the raft's folder. `./zn metrics` counts both and rolls an issue's rounds up to its raft through `raft:`.
- Code mode: `review-NNN.md`, in the raft directory.
- `NNN` continues from the highest existing number.
- Under `./zn dispatch`, in every mode, write your review to `$ZN_DISPATCH_DIR/review.md` (your own state folder) and nothing else: the dispatcher numbers it with the mode's file name and moves it into the mode's folder, and a step that wrote no review fails. The names above and in Visible record are the interactive path's, where you write the file yourself.

```markdown
# Review NNN: <R0010 | f0010> (<design | code> mode)
Inputs: <commit sha / files reviewed>

### F1 [high] <one-line claim>
Where: <path:line or doc section>
Evidence: <the concrete failing scenario, input, or quote. Not "might be" but "does X when Y">
Critique: <why it matters, and the fix the author will be tempted to make>
Consequences: <take that fix one step further: the new rules, state, edge cases or user decisions it brings, or "none">
Recommendation: <the fix that holds up after its consequences, with the spec cases or decisions it needs>
Lesson: <skill>/<slug> (only when the finding repeats an existing lesson)

### F2 [medium] ...

## Judged criteria (code mode only)
- JC1: pass | fail. <reasoning against the rubric>

Verdict: approve | changes
```

**Severity:**
- **high**: a wrong result, a crash, a security or authority hole, an acceptance criterion that's unmet or can be passed by a wrong implementation, or a regression.
- **medium**: a likely future defect, a scalability trap, an architecture rule bent, a missing test for an edge case.
- **low**: a clarity or maintainability improvement.

**Think one step further.** A finding isn't finished at "here's the fix". Say what new rule, state, edge case or user decision the fix brings, and how it interacts with existing rules, and make the Recommendation cover it, including its spec cases, so it doesn't come back as next round's finding.

**Never prescribe a cut.** Scope belongs to the user. A Recommendation never makes an outcome the issue's Problem asks for smaller, later or optional. When narrowing is the only fix you can see, the Recommendation starts `escalate to the user:` and lists the options, including what keeping the full scope would cost.

Don't pad the review. Zero findings with `Verdict: approve` is a valid result. Use `approve` only when no high or medium findings remain.

On a re-review round, first read the previous `review-NNN.md` and `refute-NNN.md`.
- If a refutation is right, drop that finding.
- If it's wrong, repeat it with the new evidence.
- If this round finds a hole in a mechanism a previous round already found one in, the Recommendation questions the mechanism, not just the hole.

## Visible record
In code mode the PR shows the review as it happens: the author pushes and posts a "started" comment before you begin, and commits, pushes and summarizes `review-NNN.md` when you finish. So:
- Write `review-NNN.md` in full (under `./zn dispatch`, `$ZN_DISPATCH_DIR/review.md`, as Output file says); findings that exist only in your reply are lost. Write only that file: don't commit, push, comment on the PR or leave other files in the tree (the author's commit uses `git add -A`).
- On a re-review, list withdrawn findings in a non-heading line under `Inputs:`, for example `Dropped from review-001: F2, F4`. Give a repeated finding a new id and say `(repeat of review-001 F3)` in its claim. Every `### F<n>` heading is a finding that `./zn done` requires an answer to, and ids restart at F1 each round.
- Design mode runs in the prep worktree before any PR exists, so it is exempt; its files are committed with the prep commit and ride in the prep PR.

## Raft mode (from z-raft)
One short round on a raft z-raft grouped from prepared issues, whose own designs were reviewed apart. Copy the raft's `grouped:` value onto a line of its own under `Inputs:`, as `Grouped: [<the value>]`: z-raft's carried move and `ready` need a review that quotes the record it read. Never edit a review once it is written: a new round is a new file. Attack only the raft: item 7 (**Raft coherence**) below, and the raft's Theme, Order & dependencies and Whole-raft design: do two members change one module, public signature or `architecture.md` edge in ways that disagree, does the order follow `depends_on` and what the interfaces force, and does the Theme quote the decisions the members rely on? Don't re-review a member's design. A finding whose fix needs a member's design to change says so: z-raft takes that member out of the raft.

## Design mode (from z-design)
Attack all of the following:
0. **Rules and mutants**: audit each issue's Rules and mutants table. Every behavioural rule in the Design needs a row. Rows marked `run` were mutation-tested on a prototype in prep, with the outcome recorded in Unknowns & experiments; check that record, and spot-run only the rows you doubt. `reasoned` rows weren't run (the reason is in Unknowns & experiments), so judge them by reading, or spot-check them with a scratch copy. A missing row, a row whose spec case can't fail, or a plausible mutant nobody listed is a finding.
1. **Unknowns**: every assumption that isn't proven, especially about Roblox or engine behavior, replication, or performance. Is each one an experiment with a pass/fail question and a fallback?
2. **Acceptance criteria**:
   - Can a wrong or hard-coded implementation pass `check.sh`?
   - Does every Checked criterion correspond to a real check?
   - Could a Judged or Observed criterion be turned into a measurable proxy?
3. **Completeness**: missing edge cases, such as empty input, bounds, simultaneous events, respawns, frame-rate independence, or player disconnects.
4. **Regressions**: which existing behavior could break, and is it guarded? Check each issue's `Overrides:` line: for every Touched path run `lune run z-nile/affected -- <path>` and `grep -rlF -e <path> tests/acceptance` (`ALL` carries no list: grep alone, also with the basename), and confirm that every promoted spec the design would turn red is named there, with its chore in `depends_on` unless the issue is itself a chore. An unnamed override, a missing line or an unfilled placeholder is **high**.
5. **Architecture**: is Logic kept pure, and are requires legal? Is every new dependency declared in `architecture.md`, and is the graph still acyclic? Is the server authoritative?
6. **Scalability, maintainability and usability**: are they addressed concretely?
7. **Raft coherence**: do the issue designs agree with the whole-raft design and with each other, and is the order right?
8. **Executability**: could an agent that has never seen this repo deliver it from the documents alone, without asking a question?
9. **Repository safety**: could any spec, `check.sh` or script in this raft change the real repository (zz-test skill, "Specs never touch the real repository")? Every command that changes anything must run in a fixture under `.cache/<unique name>` with its own repository, committing as `@example.invalid`. Check especially what the runner can't enforce (that section's "Caught only by review" list). Any path to the real repository, or any weakening of its guards, is **high**.
10. **Lessons**: run `./zn lessons --when design --full` and ask each lesson's `check` of the draft. A draft that repeats a lesson's defect is a finding, with that lesson on its `Lesson:` line. Then judge the lessons the author added since the last round (`harvest.md`): each must be a lesson a different raft could fail, not a restated finding; a restated finding is a low finding.
11. **Scope fidelity**: for each item, print its capture (`./zn capture <id>`) and compare the document with it (z-design, **Scope is what was captured**). Its title, Problem and Solution ideas may only gain detail, `Scope decision (user, YYYY-MM-DD)` lines and `Decided with the user (YYYY-MM-DD)` lines. Then check that every captured outcome has a Design and an acceptance criterion: Checked, or Judged or Observed only where the zz-test skill allows it. An outcome dropped, deferred, moved into Non-goals, reworded away or left without a criterion, with no `Scope decision` or `Decided with the user` line, or a Problem rewritten to match a smaller design, is **high**. A capture carrying any marker (`(no capture commit: …)`, `(ambiguous: …)` or `(history before … not followed: …)`) is not a confirmed capture: say so, and judge the scope from the item's history.
12. **Bounded commands**: Run every probe, experiment, loop and background command you start yourself (anything that is not the gate, a check, a `./zn` command or the spec runner) through `./zn run --time <seconds> -- <command>`: it stops at its limit, when it ends and when you do. Did the experiments and probes in the draft (and their recorded results) run that way, and does any step tell the executor to run something unbounded?

## Stream mode (zz-execute Phase 2B)
A stream review is a cheap first filter on **one issue's** work, before the lead merges the stream: in an interactive session a clean **Sonnet** subagent runs it, and under the dispatcher `./zn dispatch zz-review <issue> --mode stream` does, on the review model of the CLI. It never replaces the code review of the whole raft (Code mode, on the review model of the CLI).
- **Scope**: `git diff <raft branch>...ws-<issue>`, that issue's document, `check.sh` and acceptance specs, and from round 2 the previous review and refute text (in an interactive session the lead puts that text in the brief; it is not in the stream tree). Under `./zn dispatch`, from round 2 read the previous `stream-review-<issue>-NNN.md` and `stream-refute-<issue>-NNN.md` in the raft's folder of your worktree (the prompt names them). Run the stream's checks (`./zn check <issue>`, `z-nile/check.sh --affected`) in the stream worktree. Check that the diff touches only the issue's Touched modules and its own document. A `stream-review-*` or `stream-refute-*` file in that diff is a finding: those files live only on the raft branch.
- **Output**: An interactive subagent returns the review markdown and writes no file: the lead writes `<root>/rafts/active/<R-id>/stream-review-<issue>-NNN.md` (the raft's folder, `./zn find <R-id>`) on the raft branch. Under `./zn dispatch`, the reviewer writes its review to `$ZN_DISPATCH_DIR/review.md` (its own state folder), and the dispatcher numbers it into the raft's folder as `stream-review-<issue>-NNN.md` (the next round of that issue) in the lead's raft worktree; the reviewer reads the stream's diff and runs its checks in `ws-<issue>` (read only there). A dispatched run has no caller to return text to, and a step that spent tokens but wrote no review fails. Either way the file is in the format above (no Judged section: the code review rules on Judged criteria). Number rounds from 001; there are at most two. The author returns the refute text; the lead writes `stream-refute-<issue>-NNN.md` on the raft branch.
- These files are not review rounds: `./zn done` and `metrics` ignore them.

## Code mode (before the PR is marked ready)
Inputs: `./zn sync --fetch` (never a merge: a merge would add a commit and move the sha the author announced), then `git diff origin/main...HEAD`, the raft and issue documents, and the `check.sh` files.
A code-mode Recommendation never asks the author to edit sequestered `check.sh` files or acceptance specs, or to decide product questions. If that's the only fix, say the author must escalate (zz-execute stop conditions).
1. **Correctness**: run the code in your head against edge cases, and read the tests critically. Run `z-nile/check.sh --affected` and each `./zn check <id>` yourself.
2. **Sequestration**: `git fetch origin main && git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` must list nothing except `R100` renames (the move to `active/`). Any other change is **high**. The three-dot form shows only what this branch changed, not what `main` brought in. When a check judges the item's own sequestered files against a reviewed prep commit (c0120's AC18), an approving review records that commit as a line `Prep reference: <sha>`, and beside it the anchors the check is derived from: `Move commit: <sha>` (c0120's renames commit) and `Core commit: <sha>` (its hand-written core, the third first-parent commit after the move) (the prep commit whose `check.sh` and acceptance files you reviewed, as `git log -1 --format=%H origin/prep-<id>` gave it after your fetch). Only a reviewer writes it; never record a commit you didn't review.
3. **Weak tests**: tests that assert on internals, lack a negative case, would pass with a stub, or depend on the wall clock or randomness.
4. **Design adherence**: does the code match the Design? Is each deviation recorded with a reason? A deviation that drops or shrinks an outcome the issue's Problem asks for is **high**, and its Recommendation is to escalate (zz-execute stop conditions).
5. **Architecture rules** from the skill, including thin adapters and server authority.
6. **Performance**: per-frame allocations, O(n²) work in a tick, and replication volume.
7. **Judged criteria**: give a ruling on each against its rubric.
8. **Repository safety**: no spec, `check.sh` or script in the diff may change the real repository, run a command that changes anything outside a `.cache` fixture, or weaken a guard: `tests/lib/fence.luau`, `z-nile/lib/fence.sh`, `z-nile/lib/git-hooks/`, the fence in `z-nile/lib/ac.sh`, `tests/tooling/repo-fence.spec.luau`. Check the "Caught only by review" list in the zz-test skill's "Specs never touch the real repository" section line by line. Any such path is **high**.
9. **Fix delta** (re-review rounds): review the fix delta as well as the whole diff: `git diff <the previous review's commit>..HEAD` (the commit that added the previous `review-NNN.md`). For each fix, what new behaviour does it add, and what does that break or open? A defect in a fix is a finding like any other.
10. **Lessons**: the same as design mode's item 10, with `./zn lessons --when build --full`.
11. **Bounded commands**: Run every probe, experiment, loop and background command you start yourself (anything that is not the gate, a check, a `./zn` command or the spec runner) through `./zn run --time <seconds> -- <command>`: it stops at its limit, when it ends and when you do. Does any script, spec or step in the diff start a process nothing stops (`nohup`, `setsid`, `perl -e alarm` around `lune`, a bare `lune run` in a `check.sh`), and did the probes the author reports run through `./zn run`?

## Lessons
Before you start, read this skill's lessons: `./zn lessons --skill zz-review --full`. Each is a mistake made before, with the question that catches it.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder: `z-nile/skills/` for z-nile's skills, `<project>/skills/` for a project's, never through a `.claude/skills/` link, which git can't add through; format: zz-rules skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (z-design step 5.3, zz-execute Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (z-ticket skill). The prep that takes the issue writes the file.
