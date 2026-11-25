# Review 001: f0453 (code mode)
Inputs: origin/rework-shipped 4ce72527c12c0747826ad5f61a54f6b9863ccd97 against origin/main 3e7b197e3 (merge base = main tip); `git diff origin/main...origin/rework-shipped` (25 files), z-nile/.tracker/issues/f0453/f0453.md and check.sh. Probes ran in shared clones under the scratchpad (`./zn metrics` on main and branch, `--include-active`, `./zn audit`, a shallow clone, two Lune probes over history.read and reworkgit, the new spec: 15 passed).

Hand recomputation (from the branch's own per-issue table): 48 features, +100999 lines, 5666.6 typed minutes; 13 defects, +14462, 528.0 min; the 5 counted (d0105, d0124, d0151, d0413, d0416), +2642, 528.0 min. Shipped: 2642/103641 = 2.5%, 5/53 = 9.4%, 528/6194.6 = 8.5%. All defects: 12.5%, 21.3%, 8.5%. These match what the code prints. `./zn audit` is clean on the branch (0 errors, 0 warnings). Metrics with a warm `.cache`: 1.19 s on main, 1.45 s on the branch; in a clone with no `.cache` it goes from 1.57 s to 3.0 s, because metrics now calls history.read, which caches nothing there. A shallow clone is handled: history.read returns nil, so every defect that names a fix counts, and the report says so.

### F1 [high] d0412's recorded fix contradicts its Problem: it fixes shipped f0145, not only c0202
Where: pickman/.tracker/issues/done/d0412/d0412.md (frontmatter `fixes: [c0202]`)
Evidence: d0412's Problem says "f0145's rule 'a decline during the write is applied after it' held only when the write used a revive. Main had the same gap (`useOne` answered "none" there); c0202 rewrote both functions in this raft". So the defect was already on main, in f0145's code. f0145 reached done on main in 074a1065e ("R0118: bind f0145", 2026-11-17 06:37 PST), and d0412 was captured on 2026-11-17. With `fixes: [f0145, c0202]` (any one is enough) d0412 is shipped. With `[c0202]` (a chore in the same open raft, R0125) it is classed open and dropped. The ticket's own rule is that a fix whose Problem states it plainly is recorded, and this one is stated plainly.
Critique: the headline figure is wrong. With d0412 counted it is 6/54 = 11.1% by issues and (2642+1239)/(3881+100999) = 3.7% by lines, not 9.4% and 2.5%. The tempting fix is to argue that the bug is "in c0202's rewrite". The Problem says the opposite: main had the gap before c0202.
Consequences: the "defects not counted, the work they fix was still open" line becomes empty on the real repository. The ticket's Open-to-the-human figures for the same-day rule (9.4%/5.9%) change, because d0412 is also a same-day case (f0145 was done the same day). That gives the owner's open same-day question three defects, not two.
Recommendation: record `fixes: [f0145, c0202]` on d0412, and update the Open-to-the-human paragraph's figures and its list of same-day defects (d0412, d0413, d0416). If the author reads the Problem differently, escalate to the user with both figures; don't leave it as is.
Erred: zz-execute
Upstream: none

### F2 [high] The first-parent fallback is a second reader of "done day" that returns another item's day for reused ids, and its day disagrees with history.read's
Where: z-nile/engine/reworkgit.luau:12-36; z-nile/engine/main.luau (cmd.metrics fallback loop)
Evidence: (a) Compaction reuse. `z-nile/compaction.txt` maps R0020 to R0002 and R0200 to R0020. history.read has no day for R0020: c0118's cut logic withholds the date on purpose ("arrived under an older id, at an instant this history cannot tell"). `reworkgit.doneDay(".", "R0020")` returns 2026-09-30, the day of b76c5b0d0 "R0020: Worktrees by default (#11)". That raft is today's R0002. Today's R0020 is "Publish state to main". The same happens for R0060: the fallback gives 2026-09-30 ("Raft browser", now R0006) where the real day is 2026-10-26. R0060 only escapes because history.read has a day for it. A probe over all 291 done items found 103 with no day in history.read (R0001 to R0023 among them), and each of them goes to the fallback once a defect names it. (b) Two meanings of "done". For f0109, history.read gives 2026-10-26 (79a2a3f9c "tracker: done R0056", a commit on the PR branch) and the fallback gives 2026-11-01 (the merge e9030e564 on main). R0056 differs the same way (10-27 against 11-01). So one figure dates some ids by "committed on a branch" and others by "merged to main", up to six days apart.
Critique: this produces a wrong classification (shipped or open) on real ids. The only reason it doesn't show today is that no defect names R0001 to R0023. The tempting fix is to patch reworkgit to skip compaction commits. That leaves two readers of one fact that still disagree in meaning (b).
Consequences: one reader means history.read has to date merge arrivals (`--diff-merges=first-parent`, or `-m --first-parent`, in its log) while keeping its compaction cut. That gives `closed`/`doneAt` to 103 more items, which changes what the board and chart show for them, so those readers' specs must be rerun, and the cache key bumps (v7 to v8). Whether "done" means merged to main (the likely reading of "shipped") or committed on the branch is a definition the fix has to state.
Recommendation: date every done arrival in history.read on the first-parent line, so `closed` is the day the item reached main, keep the compaction cut, and delete reworkgit. State in zz-stats that the done day is the day the item reached main. Cases: a fixture whose compaction map gives an id to a second item (the fallback today returns the first item's day; it must return nil, or the second item's own arrival), and a fixture whose done move is committed on a branch on day X and merged on day Y > X, with a defect captured between (classed open). If changing history.read is out of reach, reworkgit must at least ignore every arrival at or before the last compaction commit that names the id as a target, and history.read must then also use the merge day, or the two readers keep disagreeing.
Lesson: zz-arch/one-reader-per-format
Erred: zz-arch
Upstream: z-design

### F3 [medium] Days are compared across time zones: raft done days are UTC, issue days and `created:` are local
Where: z-nile/engine/rework.luau:39-48 (`doneDays`, `os.date("!%Y-%m-%d", ...)`); main.luau `today()` (`os.date("%Y-%m-%d")`, local); history `closed` and reworkgit take the `%cI` committer-local day
Evidence: R0044 reached main on 2026-11-01 at 22:24 PST. `doneDays` gives it 2026-11-02 (UTC), while the fallback and every issue's `closed` give 2026-11-01. A defect captured on the evening of 2026-11-01 PST that names R0044 is classed open and dropped. The spec case "dates a fixed id by its issue day, else by its raft's instant (a UTC day)" pins the mixed convention.
Critique: the owner's rule is "done when the defect was found". For every raft and every issue dated by doneAt alone, the result now depends on the hour.
Consequences: once F2 dates arrivals by `%cI`, rafts get the committer's local day like issues, and `doneAt` is no longer used here. `created:` is the capturing machine's local day, and %cI is the committer's offset. Both are the owner's Pacific time in practice, but say so.
Recommendation: one convention, the local day of the commit's own offset (what `%cI` gives) for every done day, compared with `created:`. Replace the UTC case with one where a raft is merged at 22:00-08:00 on day D and a defect is created on day D: shipped.
Erred: zz-execute
Upstream: z-design

### F4 [medium] The ruling line is not tied to the `shipped:` key, and the limit of the guard is not stated where reviewers would act on it
Where: z-nile/engine/rework.luau:19-28 (`hasRuling` scans every line of the document); audit.luau unhonoured-shipped
Evidence: `hasRuling` accepts any line in the document that starts `Ruled (user, YYYY-MM-DD): "..."`: inside a ``` fence, as a sub-bullet answering an unrelated question under `## Open to the human` (for example `  Ruled (user, 2026-12-01): "keep the old menu"`), or in a pasted example. So a defect that carries any quoted ruling about anything, plus a typed `shipped: no`, is dropped and audit stays silent. Elsewhere the tracker binds a ruling to its subject: openlist reads `Ruled (user, …)` on the bullet of the finding it answers. The limit is that nothing can tell an owner's words from an agent's. What actually protects the key is review: `shipped:` is not a capture key, so adding it needs a PR. But no review checklist says to check where the quoted words came from.
Critique: as written, the guard catches only a key typed with no ruling line at all. The design's claim ("an agent cannot remove a defect from the figure by typing the key") holds only against an agent that types the key without the line. The tempting fix is a stricter regex, which still matches any line anywhere.
Consequences: a line format that names the key needs one reader used by audit and metrics (`rework.isRuled` already is that reader). The seven existing lines would be rewritten to the new form, in this PR, with the same quoted words.
Recommendation: honour only a line that names the key, e.g. `Ruled (user, YYYY-MM-DD), shipped: no: "<words>"`, outside fenced code. Have audit refuse a document with two such lines, or with one dated before `created:`. State the limit plainly in zz-stats ("the line is a quotation; review checks it"), and add to zz-review code mode: a diff that adds `shipped:` or a ruling line must name, in the PR, where the owner said those words. Cases: a ruling inside a fence is not honoured; an unrelated `Ruled (user, …)` line beside `shipped: no` is not honoured and is the audit error; the keyed form is honoured.
Erred: zz-execute
Upstream: z-design

### F5 [medium] `fixes:` can drop a defect with no guard at all, and it is a capture key
Where: z-nile/engine/audit.luau (unknown-fixes checks existence only); main.luau CAPTURE_KEYS now includes `fixes`
Evidence: a defect whose `fixes:` names itself is done after it was captured on any later day, so it is classed open and dropped. A non-emergent defect whose `fixes:` names its own `raft:` (the raft that fixes it, done after capture) is dropped the same way. Audit accepts both, since the ids exist. Because `fixes` is a capture key, such an edit to a backlog defect reaches main through `./zn land` after the static stages only, with no PR. So `shipped: no` needs a quoted ruling, but `fixes: [<self>]` needs nothing and has the same effect.
Critique: the defect is still listed on the "not counted, still open" line, so this is visible, not silent. That is why this is medium. But the guard's purpose is defeated by the neighbouring key. The tempting fix is to forbid a defect naming its own raft. That is wrong for an emergent defect: d0412 sits in R0125 and fixes R0125's open work, the legitimate "open" case.
Consequences: the rule has to tell emergent defects from non-emergent ones (an emergent defect's raft is the open work it was found in; a non-emergent defect's raft is the raft that fixes it).
Recommendation: audit error `self-fixes` when a defect's `fixes:` names its own id, or names its own `raft:` while `emergent:` is not true. Cases: each of the two is an error, and an emergent defect naming its own raft or a member of it is silent.
Erred: zz-execute
Upstream: z-design

### F6 [medium] The path that files the defects the Problem is about (emergent defects found inside open work) is not told to record `fixes:`
Where: z-nile/skills/zz-rules/SKILL.md, Emergent issues step 1 (`./zn new issue d <slug> --raft R0010`); zz-execute's emergent step; only z-idea step 2 names `--fixes`
Evidence: the Problem's case is "a problem found and fixed inside a feature that was still open". Those defects are filed by the emergent path. Its rule doesn't mention `--fixes`, so every future one is unrecorded and counted as shipped, which is the figure the owner asked to stop counting. d0410, d0412 and d0413-style defects are all emergent or raft-time captures.
Critique: the change fixes the past by hand and leaves the main future writer producing unrecorded defects. The tempting fix is to add a sentence to z-idea only, which is the step already changed.
Consequences: `new issue d --raft R…` with no `--fixes` could default `fixes:` to that raft. That is consistent with the owner's "found inside open work never counts" and is allowed by F5's emergent exception. Otherwise it prints a reminder. Either way the skills that file defects (zz-rules Emergent issues, zz-execute, and watch-net's filer if it files defects) must agree (lesson z-design/restated-rules-move-together).
Recommendation: zz-rules Emergent issues step 1 and zz-execute name `--fixes <the member or raft whose work it fixes>`, and `new issue d --raft` without `--fixes` writes `fixes: [<that raft>]`. Case: an emergent defect created without `--fixes` carries its raft and is classed open while the raft is open.
Lesson: z-design/restated-rules-move-together
Erred: z-design
Upstream: none

### F7 [medium] escalate to the user: counted defects that the owner's own criterion reads on were never put to the owner
Where: d0151, d0416 (and d0413) frontmatter `fixes:`; f0453 Problem (the ruling covered only "the seven defects with no recorded fix")
Evidence: which defects went to the owner depended on which ones the author recorded a fix for. d0151 (0 lines) was closed because it did not reproduce. Its own record: the retest showed the swipe, look drag and snap work. d0416 changes only a stale promoted spec (its Scope decision: "the engine does what d0415 designed … the c0117 case is stale"), and the defect it fixes, d0415, is one the owner ruled did not ship. d0413 is main's red gate after f0399 (a loop-scan list), though it also names a real hang in `depsFirst`. The owner's criterion was "something was done wrong, or not yet implemented more than the functionality was actually broken". It plausibly covers d0151 and d0416, but the owner was only asked about the other seven.
Critique: a reviewer must not decide this, and neither should the author. The figure is the owner's.
Consequences: a ruling would be recorded with F4's keyed line form.
Recommendation: escalate to the user: put d0151, d0416 and d0413 to the owner in plain words, with what each answer does to the figure. From the current 5 counted (before F1): dropping d0151 gives 4/52 = 7.7% by issues, dropping d0151 and d0416 gives 3/51 = 5.9%, and dropping d0413 too gives 2/50 = 4.0%. By lines added, d0151 and d0416 add 0 and 10 lines, so only d0413 moves it (2642 to 2350). Agent time does not move. Keeping all of them counted is also an answer.
Erred: zz-execute
Upstream: none

### F8 [high] escalate to the user: f0453 skipped the pipeline: no capture on main, no idea challenge, no design review, no raft, and its check.sh is written on the code branch
Where: z-nile/.tracker/issues/f0453/ (frontmatter `idea: unchallenged`, `design: draft`, `raft:` empty); z-nile/next
Evidence: `git diff --name-status origin/main...origin/rework-shipped -- '*/.tracker/**/check.sh'` lists `A z-nile/.tracker/issues/f0453/check.sh`, an addition, not an R100 rename. The ticket, its acceptance check and the code that passes it were written on one branch. The folder holds no idea-review, design-review or harvest. The id is reserved nowhere on main (`origin/main:z-nile/next` is `issue 450`), so it already collided once (f0449 renumbered to f0453 when c0449 took 449), and any capture before this merges takes 0450 again.
Critique: zz-review treats a changed check.sh as high, because a check written with the code can be passed by a wrong implementation (F1 to F3 are exactly what a design review exists to catch). The owner may have allowed this route in the session. Nothing in the ticket records that.
Consequences: if the owner allows it, the ruling belongs in the ticket as a `Decided with the user` line, and the counter should be reserved on main now.
Recommendation: escalate to the user: either the ticket goes through capture, design review and a raft (the check.sh then reviewed in prep), or the owner rules that it lands as one PR, recorded in the ticket with the words used. In both cases reserve the number now with a counter-only publish so 0450 cannot be taken again.
Erred: zz-execute
Upstream: z-idea

### F9 [low] Design deviations not recorded: README and template, and an empty Verification log that a Non-goal points to
Where: f0453.md Touched modules and Report ("`zz-stats/SKILL.md` and the README state the new formula"); Non-goals ("Kept as they are (listed in Verification log)"); `## Verification log` is empty
Evidence: z-nile/README.md and z-nile/templates/issue/doc.md are not in the diff. The README states no rework formula at all (only line 224, "the rework rate"). The template doesn't need the key, since `--fixes` writes it.
Critique: a reader of the ticket expects changes that are not there.
Consequences: none.
Recommendation: drop README and template from Touched modules with one line why, and fill the Verification log with what the Non-goal says it lists (the board and chart ratios kept), plus the probe timings.
Erred: zz-execute
Upstream: none

### F10 [low] Mutants the spec does not kill, and a misleading audit message
Where: z-nile/tests/tooling/rework-shipped.spec.luau; audit.luau unhonoured-shipped
Evidence: no case kills: dropping `not first["raft:" .. fixed]` from unknown-fixes (no case names an existing raft); removing `fixes` from CAPTURE_KEYS; deleting the `type: defect` refusal of `--fixes` (no `new issue f --fixes` case), the bad-id refusal or the empty-list refusal; dropping `--first-parent` from reworkgit (the fixture's side branch adds no tracker file, so the result is the same). `shipped: yes` beside a ruling line produces the audit message "with no Ruled … line", which is false.
Critique: the AC3 behaviours beyond the happy path are unpinned.
Consequences: none.
Recommendation: add one case per mutant above (a raft id in `fixes:` is silent; a capture diff that edits `fixes:` passes captureScope; `new issue f --fixes` fails; `--fixes ,` and `--fixes f33` fail; a side branch that adds the done document on an earlier day than the merge). Make the audit message say "shipped: must be no" when the key has another value.
Erred: zz-test
Upstream: none

### F11 [low] "by agent time" reads only typed minutes, so none of the recent defects reach it
Where: cmd.metrics rows (`minutes` = the `reported` column), shown by the new "all defects" line
Evidence: all eight defects this change drops have 0.0 typed minutes (d0297 has 12188 s wall, d0383 8955 s), so agent time is 8.5% before and after. The new side-by-side line makes it look as if the change did not touch time, when the measure ignores measured-only rows. This predates f0453.
Critique: the owner will read the unchanged 8.5% as a finding about rework.
Consequences: none here.
Recommendation: no change in f0453. Tell the owner in the PR that agent time covers typed minutes only, so recent work is not in it.
Erred: none
Upstream: none

## Judged criteria (code mode only)
- (none: f0453 states Checked criteria only)

Verdict: changes
