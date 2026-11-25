# Review 002: f0450 (code mode)
Inputs: origin/rework-shipped 5358f6fbd19e03471638bdef638f1abe7657fcc9 (round-1 head 4ce72527c), origin/main 6b7f4e459fed7c3f527ce5395defdc0e23710e5d (merge base 3e7b197e3); review-001.md, refute-001.md, `git diff 4ce72527c..origin/rework-shipped`. Probes ran in shared clones in the scratchpad, with refs/remotes/origin/main set to the real origin/main: metrics and board, warm and cold, on main and on the branch; a Lune probe that compares main's history.luau with the branch's on the same tree; `git log --first-parent` per id; `./zn audit`; the spec (18 passed); a trial merge of origin/main.

Round-1 answers:
- F1 fixed. d0412 has `fixes: [f0145, c0202]`. f0145 reached main 2026-11-17 (074a1065e), the capture day.
- F2 fixed. On the same tree, history.read's `closed`, `spells`, `doneAt`, `activeAt`, `warnings` and `today` are identical under main's history.luau and the branch's, so board and chart get the same data; only the time changes (N2). `doneDay` matches `git log origin/main -m --first-parent --diff-filter=A` on every dated id checked: the nine tickets the six counted defects name (f0024, f0025, f0061, f0027, f0028, f0029, f0145, c0202, f0399, d0415; f0033 is undated), ten random ids (R0034 10-21, c0279 11-09, f0205 11-17, c0266 11-15, d0297 11-17, R0036 10-18, d0416 11-19; c0049, R0010 and f0014 undated), plus R0044 11-01, f0109 11-01 (the merge day, no longer the branch commit's 10-26) and R0060 10-26 (the reused id now gets its own day, not the old raft's 09-30). R0020 is now undated, not misdated. reworkgit.luau is deleted. The cache key is `v8 <HEAD> <origin/main> <roots>`, so a v7 cache never matches and is re-read.
- F3 fixed. `doneDay` is the `%cI` local day for issues and rafts alike (R0044 is 11-01).
- F4 fixed. Only the keyed line outside a ``` fence is honoured, and the seven tickets carry it with the same words. Small leftovers in N3.
- F5 fixed. `self-fixes` exists; audit on the branch has 0 errors and 0 warnings; d0412 (emergent, raft R0125, fixes f0145 and c0202) is silent.
- F6 fixed. `new issue d --raft R` writes `fixes: [R]`. That is emergent and so silent for `self-fixes`, and classed open while the raft is open. zz-rules and zz-execute name `--fixes`.
- F7 escalated. The figures in Open to the human are right (9.4%, 7.7%, 5.9%).
- F8 not resolved, and it has now caused the collision in N1.
- F9 fixed.
- F10 fixed. 18 cases pass.
- F11 fixed in text, except one wrong clause (N4).

Q2, the 76 undated items: every undated id first arrives on the main line in the compaction commit a38f91f98 (2026-10-05), or is a cut id (R0020). So each was done on or before 2026-10-05, and counting a defect against one is the stricter reading. Only a defect captured before 2026-10-05 could be counted wrongly, and none is. Sound.

Q5, hand recomputation: 48 features (+100999 lines, 5666.6 typed minutes). 6 counted defects (d0105 203, d0124 2137, d0151 0, d0412 1239, d0413 292, d0416 10, so +3881; 528.0 min). 3881/104880 = 3.7%, 6/54 = 11.1%, 528/6194.6 = 8.5%. All 13 defects: 12.5%, 21.3%, 8.5%. These match the printed lines, cold and warm (the two outputs are byte-identical).

### N1 [high] The id f0450 is now taken on main by another ticket: the branch cannot merge, and a careless merge loses that ticket or lowers the counter
Where: z-nile/.tracker/issues/f0450/ (both sides); z-nile/next (branch `issue 451`, main `issue 453`)
Evidence: origin/main 7154ee0ee, "tracker: new f0450 close-work-already-on-main" (2026-11-24 23:33 PST), then d0451 and f0452. A trial merge of origin/main into the branch gives `CONFLICT (add/add)` in `z-nile/.tracker/issues/f0450/f0450.md` and `check.sh`, and `CONFLICT (content)` in `z-nile/next`. This is the second collision of this ticket's id; round 1's F8 named the risk. Resolving the merge to the branch's side would overwrite main's f0450 ("close work already on main"). Taking 451 for `z-nile/next` would lower the counter: d0451 and f0452 already exist, so the next captures would reuse those numbers. A PR merge goes past the publish guard that keeps counters rising.
Critique: answer Q6 with no: merging this branch to reserve the id does harm now. The tempting fix is to resolve the conflict by hand in the merge. That keeps "f0450" in code comments, skills, the spec and the printed metrics line ("the figure before f0450"), all of which would then point at the other ticket.
Consequences: renumbering touches the ticket folder (review-001, refute-001, check.sh), the watch file, the spec's case names and texts (9 references), the engine comments (audit 2, history 4, main 4, rework 2, including the printed "(the figure before f0450)"), and the skills (z-idea, zz-review, zz-rules, zz-stats). The prepared capture branch `capture-f0450-rework` (counter 451) is stale too.
Recommendation: before any merge, renumber this ticket to the next free id on origin/main (453 or later, reserved by a counter-only publish first), and rewrite every "f0450" in the branch's own files to it. Leave main's f0450 alone. Merge origin/main with `z-nile/next` at main's value or higher. Then rerun the spec, `./zn audit` and the static stages. Add a spec text pin or grep that the printed line names the new id.
Erred: zz-execute
Upstream: z-idea

### N2 [medium] The board pays a second full history log for a field only metrics reads
Where: z-nile/engine/history.luau `history.read` (the mainLog parse runs on every uncached read); board.luau:918 is the other caller
Evidence: cold `./zn board`: 2.82 s on main, 4.42 s on the branch. Cold `./zn metrics`: 1.35 s on main (it did not read history), 4.47 s on the branch. Warm, both are about 1.2 s. The cache key now includes origin/main's sha, so every fetch, publish or land makes the next board refresh cold, and the board is refreshed after every publish and land (AGENTS.md). The board never reads `doneDay`.
Critique: this adds about 1.6 s to every board refresh, and to every spec fixture that renders a board, for nothing the board uses. The tempting fix is to fold the main-line read into the one log by adding `-m --first-parent` to it. That would change `closed`/`doneAt`/`spells` for every reader, which this round just showed are unchanged.
Consequences: an opt-in read needs its own cache entry (or the same file, with the field present only when asked for), and metrics must ask for it.
Recommendation: read `doneDay` only when the caller asks (`history.read(root, { doneDay = true })`, or a separate `history.doneDays(root)` cached under its own key `<origin/main sha> <roots>`). Board's cold time then goes back to main's. Add a case that board's read runs one `git log` (count the processes by the `--first-parent` flag, lesson zz-test/count-processes-by-their-own-arguments).
Lesson: zz-test/count-processes-by-their-own-arguments
Erred: zz-execute
Upstream: none

### N3 [low] The ruling line can still be honoured from inside code that is not a backtick fence
Where: z-nile/engine/rework.luau `isRuled`
Evidence: the fence toggle reads only lines starting "```". A `~~~` fence, a four-space indented code block (`^%s*` accepts the indent) and an HTML comment spanning lines all still honour a keyed line inside them.
Critique: review is the stated guard (zz-review 11a), so this is a small hole.
Consequences: none.
Recommendation: also toggle on `~~~`, and accept the line only with at most three leading spaces (Markdown's code-block limit). Add a case for each.
Erred: zz-execute
Upstream: none

### N4 [low] Two wrong sentences in the report and ticket
Where: rework.luau lines(), the "undated" line; f0450.md Open to the human, the agent-time bullet
Evidence: the undated line always gives the cause "(a compaction renumbered it)". Run on a branch where the fixed ticket is done but not yet on origin/main, or with a stale origin/main, the same line appears for a different cause. The ticket says "(d0105 and d0412 carry typed minutes)". d0412 has 0.0 typed minutes; the three with typed minutes are d0105 (145.9), d0124 (334.9) and d0151 (47.2).
Critique: both mislead the owner reading them.
Consequences: none.
Recommendation: word the line "done, but no day on origin/main's line (renumbered by a compaction, or not yet on main)", and correct the bullet to name d0105, d0124 and d0151.
Erred: zz-execute
Upstream: none

Verdict: changes
