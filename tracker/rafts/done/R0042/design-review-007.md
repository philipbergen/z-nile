# Review 007: R0042 (design mode)
Inputs: prep-z-nile at d13f461 (R0042.md, check.sh, harvest.md, design-review-006.md, design-refute-006.md; c0111 and c0119 documents, check.sh files and acceptance specs; the 20 lesson files; c0112.md). The prototype `.worktree/proto-scope-fidelity`, whose tracker items and lessons are byte-identical to this tree (only `design-refute-006.md` is missing there). origin/main at fetch time.
Every round-006 refutation was checked against the tree and holds, so no round-006 finding is repeated. Settled user decisions (2026-10-20) are not reopened.

Run on the prototype: c0111's and c0119's acceptance specs (`46 passed, 0 failed, 9 spec files`); `luau-lsp analyze --base-luaurc=.luaurc --platform=standard` of both acceptance folders and `scripts` (exit 0); `lessons --check` (`20 lessons, 86 harvest entries, ok`); `--uncovered R0042 R0040` (covered); the four specs that run `tracker.sh metrics` and aren't in c0111's AC7 list (`metrics-rounds`, `c0084/metrics-phases`, `c0043/rounds`, `c0053/commands-sync`): 16 passed. I didn't run `promote-check R0042`, because it writes copies into the prototype's `tests/`. The analyze run covers its type check.

Lessons pass (item 10): I asked each design lesson's `check` of the draft. Failed: `testing/no-vacuous-pass` (F1), `testing/seed-every-enumerated-case` and `testing/pin-call-site-arguments` (F2), `ticket-prep/never-narrow-captured-scope` (F3) and `ticket-prep/restated-rules-move-together` (F4). The others pass or don't apply. The new lesson `ticket-prep/specify-every-named-artifact` is general (any design that names a file can fail it) and sources two findings of different rounds, so it's a real lesson. The edited `never-narrow-captured-scope` check is general too, but it carries F1's lookup and F4's one-form wording.

Scope fidelity (item 11): c0119's title, Problem and Solution differ from its capture (ab750c0) only by the "Decided with the user (2026-10-20)" block. Every captured outcome has Design text and AC1 or AC2. c0111 (capture ef5a7a5): the title and Problem have only gained four `Scope decision` lines. Every captured Solution idea is delivered or covered by a decision line (metrics: AC9; tags-matched prompt: "All build lessons"; the R0039 seed: c0112, whose Solution still lists it). But the Solution text was replaced (F3).

### F1 [high] The capture lookup finds nothing for any item created before the compaction, so item 11, the ready-raft scope check and the one-time audit pass vacuously for half the audited members
Where: ticket-prep paragraph **Scope is what was captured.**, review item 11, ready-raft step 2 (Appendix); lesson `never-narrow-captured-scope` (How to apply); scope-docs.spec (pins the command); R0042 Risks (the audit list)
Evidence: `git log -1 --format=%h --grep '^tracker: new [fdc][0-9]' origin/main -- <doc>` prints nothing for every open member except the c011x ones. I ran it on each preparing, prepared or active issue on origin/main. It's empty for f0027, f0028, f0029 (R0012), c0083 (R0030), c0075 (R0039) and active f0065, which is 5 of the 10 members in R0042's audit list. There are two causes:
- `tracker: compact ids (#64)` (a38f91f) renamed every item, and `git log -- <path>` doesn't follow renames. c0083 was captured as `cda52f9 tracker: new c0890 …` at `tracker/issues/c0890/c0890.md`.
- Adding `--follow` doesn't fix it: `git log --follow --grep … -- tracker/issues/c0083/c0083.md` also prints nothing, because grep-filtered commits break git's rename tracking. Only an unfiltered `git log --follow --format='%h %s' --name-only` reaches cda52f9.
- Some items never had a `tracker: new` commit. f0027 came from `a985927 Game design decisions and backlog …` as `tracker/issues/f0260/f0260-touch-turn-controls.md`.

None of the texts says what to do when the lookup is empty. A reviewer or ready-raft agent then has no capture to diff against, and reports nothing to check. The next `compact` renames every item again, and after that the lookup fails for all of them. Round 006's audit list was built from "the commit that added its document". For a compacted item that commit is the compaction itself, so any rewrite made before a38f91f is invisible in that list.
Lesson: testing/no-vacuous-pass
Critique: the obvious fix is to add `--follow`. On its own it still prints nothing, and it leaves the no-capture items and the compaction's id rewrites (every `c0890` becomes `c0083` in the diff) unhandled.
Consequences: the lookup needs three parts: follow renames without `--grep`, show the file at the path it had in that commit, and fall back for items with no capture subject. The diff also shows compaction's id rewrites, which aren't scope changes. The command is pinned in three skills and in scope-docs.spec, so all of them move together (F4). The audit list has to be rebuilt with the new lookup, and it may name more members.
Recommendation: put the full lookup in one place, the ticket-prep paragraph, and have item 11, ready-raft and the lesson point to it:
- run `git log --follow --format='%h %s' --name-only origin/main -- <doc>`;
- the capture is the newest commit whose subject matches `^tracker: new [fdc][0-9]`, taken at the path listed under it (`git show <h>:<that path>`);
- if no subject matches, the capture is the oldest commit in that output (the document's first add), and the reviewer says the fallback was used;
- id changes listed in `tracker/compaction.txt` are not scope changes.

Then:
- pin `--follow`, the fallback sentence and `compaction.txt` in scope-docs.spec, with a row for each mutant (no `--follow`; `--grep` kept with `--follow`; no fallback);
- record in c0119's E-section a scratch run of the lookup over every open member on origin/main, each finding a capture;
- rebuild the audit list in R0042's Risks from that run.

### F2 [medium] The metrics fixture never moves a raft and makes one commit, so dropping `--follow`, or reading the cutoff from the wrong file, passes AC9 and misfiles every raft moved after lessons land
Where: c0111 Design, Metrics ("The reader … `git log --follow --diff-filter=A`"); metrics-lessons.spec, case "tracker.sh metrics prints …"; Rules and mutants (only "pass no cutoff" covers the reader)
Evidence: the fixture's single seed commit adds `scripts/`, both rafts and their reviews, with R0010 and R0020 in `tracker/rafts/`. So every `start` and the cutoff are the same time, and each raft's review file has one add line. Mutants that pass it:
- (a) drop `--follow`;
- (b) take the newest line instead of the oldest;
- (c) take the cutoff from any other seeded script.

On the real tree (a) matters. `git log --diff-filter=A -- tracker/rafts/done/R0001/design-review-001.md` gives `a38f91f compact ids`, while `--follow` gives `f33e77f` (R0010 at the time). R0012, R0030 and R0035 were reviewed before lessons, but `done` will move them into `done/` after lessons land. Without `--follow` they would count as "after", which is the wrong way round for the captured outcome ("show whether lessons reduce review rounds").
Lesson: testing/seed-every-enumerated-case, testing/pin-call-site-arguments
Critique: a row added for "drop `--follow`" with no fixture change would be marked `run` while its mutant survives.
Consequences: the fixture needs commits at different times, made in the fixture clone under `.cache/lessons-metrics` with its `@example.invalid` identity (repository safety holds). `GIT_COMMITTER_DATE` is set for one commit only, through `fixture.exec` with `env`.
Recommendation: in the metrics case, after `trackerfix.new`:
- commit an R0030 `design-review-001.md` in `f.main` with `GIT_COMMITTER_DATE` set before the seed commit, so it is "before";
- `git mv` R0030 into `tracker/rafts/done/` in a normal commit;
- assert `| before | 1 | 1 | 1.0 |`, and keep R0010 and R0020 "after".

This kills (a). Deleting R0030's review and adding it back in a later normal commit gives a second add line, which kills (b). Add rows for (a) and (b), run on the prototype, and record them in E4. A fixture can't kill (c), because every seeded script shares the seed commit. List it as a `reasoned` row: the path is one literal in `cmd.metrics`.

### F3 [medium] c0111's captured Solution was replaced, not detailed, and nothing in c0119 tells a prep author to keep captured Solution ideas
Where: c0111 `## Solution` (diff against ef5a7a5); c0119's ticket-prep paragraph and ready-raft step 2; make-issue step 4
Evidence:
- c0111's Solution at capture was nine bullets (one file per lesson, `tracker.sh lessons … It is a search, not a gate`, the two ticket-prep steps, the review skill, ready-raft, metrics, seed lessons). It's now one new paragraph.
- The user ruled "Yes, they're scope", and item 11 says Solution ideas "may only gain detail" and decision lines. Round 006 F6 restored the Problem's bullets verbatim for exactly this reason. The Solution got no such treatment.
- No outcome is lost: each idea maps to Design or to a decision line. But c0119's ready-raft step ("match its capture apart from added detail and decision lines … If one doesn't, stop and ask the user") stops on this document.
- The same is true of most prepared work. The Solution of c0106, f0100, f0101, f0102 and f0104 differs from its capture on origin/main.
- ticket-prep never mentions the Solution section except in the scope paragraph. Preps routinely rewrite it, as this one did, so the ready-raft check will stop on nearly every raft and ask the user about wording.
Lesson: ticket-prep/never-narrow-captured-scope
Critique: the tempting fix is to restore c0111's bullets. That fixes one document and leaves the habit that caused it.
Consequences: a rule that prep keeps the captured Solution bullets and adds below them gives the diff a clear "added detail" shape. Old prepared rafts still differ, and the ready-raft audit already covers them.
Recommendation:
- Restore c0111's nine captured Solution bullets verbatim, and keep the current paragraph after them as detail. Mark each superseded bullet with the decision that changed it, for example "(changed: Scope decision 'Accept them')".
- Add to the ticket-prep paragraph: "Keep the captured Solution bullets as they are and add your detail after them; a captured idea you would replace goes to the user."
- Add one assertion and one row (mutant: drop the sentence) to scope-docs.spec.

### F4 [low] Restated scope rules disagree: c0119's Design and R0042's diagram still say "origin/main" and "Checked", and item 11's high clause and the lesson's check accept only the `Scope decision` form
Where: c0119 Design, the lessons bullet ("the Problem on `origin/main` … a Checked criterion"), and Usability ("a diff of the Problem against `origin/main`"); R0042 Whole-raft design diagram ("captured Problem on origin/main", "diff vs origin/main"); review item 11 ("with no `Scope decision` line"); lesson `never-narrow-captured-scope` check ("backed by a `Scope decision (user, YYYY-MM-DD)` line")
Evidence: the round-006 fixes (F2 capture baseline, F5 acceptance criterion) changed the Appendix and the lesson file, but not these summaries. The ticket-prep paragraph and item 11's first sentence count both `Scope decision (user, …)` and `Decided with the user (…)` lines. Its last sentence and the lesson's check count only the first. c0119 records its own round-006 decisions in the second form.
Lesson: ticket-prep/restated-rules-move-together
Recommendation: reword the two c0119 sentences and the diagram to "the capture" and "an acceptance criterion". In item 11's last sentence and in the lesson's check, write "with no decision line (`Scope decision` or `Decided with the user`)". Pin the item-11 wording in scope-docs.spec. Do it together with F1's lookup text.

Verdict: changes
