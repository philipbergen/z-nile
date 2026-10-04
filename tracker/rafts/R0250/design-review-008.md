# Review 008: R0250 (design mode)
Inputs: prep-ready-raft at 0c1a0b2. Read: `design-review-007.md` and `design-refute-007.md`; the c0780 and c0790 documents, `check.sh` files and acceptance specs (diff 671fd02..0c1a0b2); `scripts/tracker/main.luau` (`cmd.new`, `publishing`, `mergeOrigin`, `cmd.status`'s listing) and `scripts/tracker/publish.luau` (`publish.allowed`); `tracker/templates/issue/doc.md`; the tracker and make-issue skills.

Checked against refute 007:
- **F1 (self-promotion)**: fixed. Design step 3, AC2, the Rules row, the `check.sh` AC2 label and the tracker-skill wording all say "M only, draft on both sides, status unchanged". The two new sub-cases work on the fixture: `new` writes the stub from the template (`design: draft`) with `withFront(doc, "status", stamp("new"))`, so both `gsub`s change the file, the commit is non-empty, and each diff is one `M` of the capture's own document. A mutant that reads only `origin/main`'s copy lands the `design: ready` edit, and one that doesn't compare `status:` lands the second edit, so both are killed.
- **F2 (`A` rules)**: fixed by refusing every `A`. The c0980 sub-case adds `c0980.md` and `check.sh`. The diff sorts `c0980.md` before `check.sh` (`0` < `h`), so an implementation that allowed an `A` of `<ID>.md` would name only `check.sh`, and the path assertion would fail. The mutant is killed.
- **Fixture state per reset**: land's own merge of `origin/main` is a no-op in every sub-case. Nothing is pushed between sub-cases, and `mergeOrigin` after `new` already brought the stub in. So `reset --hard HEAD~1` always returns to the capture commit, and git removes the emptied `acceptance/`, `done/c0990/` and `c0980/` directories.
- **c0790 F4**: fixed in the Design (quarter clamp, today's fallback, `periods` optional). `board-stats` asserts `periods == nil` for the undated tree, and `stats.spec` unwraps it.
- **c0790 F3**: only half fixed; see F3.

### F1 [high] Since every `A` is refused, no sub-case isolates land's path rule. A land that reuses `publish.allowed`, or that checks only `.md` frontmatter, passes AC2 and pushes edits to a draft raft document or to the issue template
Where: c0780 Design step 3 ("exactly `tracker/issues/<ID>/<ID>.md`, a backlog issue … rafts … refused"); `land.spec.luau:130-140, 167-195`; Rules row "only backlog issue documents" (mutant "no scope check") and row "only M of draft backlog `<ID>.md`…" (mutant "a `tracker/issues/` prefix check")
Evidence:
- Every sub-case that is meant to test the path is now an `A`:
  - `scripts/extra.txt` (the "outside" case);
  - `acceptance/x.spec.luau`;
  - `done/c0990/c0990.md`;
  - `c0980`.

  The `A` rule alone refuses all four, so they no longer test the path. The only `M` lines are the deletion (a `D`), `check.sh` (its own rule), and the three edits to backlog `<ID>.md` files (the draft and status rules).
- Mutant A, the natural reuse of existing code (`cmd.status` already filters with it, `main.luau:564`): an `M` passes if `publish.allowed(p)`, `p` ends in `.md`, `stateOfPath(p) == "backlog"`, both copies say `design: draft`, and `status:` is unchanged. It passes every case in the spec. `publish.allowed` accepts `tracker/rafts/R0xxx/R0xxx.md`, so a capture's edit to a draft raft document under prep (status `preparing-…`, published by `tracker.sh status`) goes to `main` without a PR. The Design forbids exactly that.
- Mutant B: anything not `A`, `D` or `check.sh` passes if it has `design: draft` on both sides and the same `status:`. That rule refuses scripts (they have no frontmatter), but it passes `tracker/templates/issue/doc.md`. That file is in the fixture (the seed copies `tracker/templates`), it says `design: draft`, and it has no `status:` on either side, which counts as "unchanged". A capture that tweaks the issue template lands it.
- The two Rules rows still claim these mutants are killed by "land refuses a change outside…" and the acceptance sub-case. After F2's fix, neither case can fail for that reason.
Critique: the tempting fix is to turn the "outside" case into an `M` of a script. Mutant B already refuses a script (it has no draft frontmatter), so that alone still leaves both mutants alive.
Consequences: the new sub-cases need `M` targets that already exist on `origin/main` and carry `design: draft` with an unchanged `status:`, so that only the path rule can refuse them. The f0600 setup push in "refuses anything but…" is the place to create the raft one. The template is already in the seed. No new user decision is needed: the Design already refuses both.
Recommendation:
- In the "refuses anything but…" setup push from `other`, also add `tracker/rafts/R0900/R0900.md` with `---\nid: R0900\ndesign: draft\nstatus: preparing-a-b-c\n---\n`.
- Add two `refused` sub-cases:
  - append a line to `tracker/rafts/R0900/R0900.md`, expecting that path;
  - append a line to `tracker/templates/issue/doc.md`, expecting that path.
- Rewrite the Rules rows' mutants as "`publish.allowed` reused (rafts pass)" and "draft frontmatter decides, not the path (template passes)", both killed by these sub-cases.
- Optionally make the "outside" case an `M` (append to `.gitignore`), so it tests what its name says.

### F2 [medium] The "draft on both sides" rule is pinned only for `origin/main`'s copy. A land that reads only the working-tree copy lets a capture demote a prepared issue to `design: draft` and rewrite it
Where: c0780 Design step 3 (first bullet); `land.spec.luau:180-187`; the Rules row "draft checked on origin's copy only"
Evidence:
- The f0600 sub-case edits only the body, so the new copy still says `design: ready`. An implementation that reads only the file on disk (the cheapest check: no `git show origin/main:<path>`) refuses it, and refuses the capture's own `design: ready` edit, so it passes the whole spec.
- On a real prepared issue (`design: ready`, `status: prepared-…`), a capture that sets `design: draft` and rewrites its Design or AC leaves `status:` unchanged. That passes both of the mutant's rules, so the prepared issue's reviewed design is changed on `main` with no review. That is the hole review 007 F1 closed, opened from the other direction.
- The Rules row lists only the origin-only mutant.
Recommendation:
- Add a sub-case: in f0600's document, replace `design: ready` with `design: draft` and append a line. Expect refusal naming `tracker/issues/f0600/f0600.md`, with nothing pushed.
- Add "draft checked on the new copy only (demotion)" to the row's mutants.
- To mirror real prepared issues, give f0600's setup document a `status: prepared-a-b-c` line, so the case also shows that the status rule alone doesn't catch a demotion.

### F3 [low] The rule that an item first seen in `done/` gets no spell (repeat of review 007 F3) is in the Design, but no spec case or Rules row pins it
Where: c0790 Design `history.parse` (close-day bullet); `history.spec.luau:65-66, 142`; Rules and mutants table
Evidence:
- Refute 007 says "fixed", and the Design sentence is there.
- The history spec still asserts only `parsed.closed.c0040`. c0040 is added straight into `done/` with `status: active-m-n-o`.
- An implementation that starts an `active` spell from that status line and closes it in the same commit gives a zero-length spell, with n=1. It passes AC5.
- The table has no row for the rule.
Recommendation:
- In the close-day case, assert `#(parsed.spells.c0040 or {}) == 0`, or assert `stats.durations` over c0040 gives `active.all.n == 0`.
- Add a Rules row: "first appearance in `done/` starts no spell", with the mutant "status handled before the close".

### F4 [low] The tracker skill's direct-push bullet will contradict land unless its existing sentence is reworded, not just extended
Where: c0780 Design, Skills ("in 'The direct-push exception', add that `land` pushes…"); `.claude/skills/tracker/SKILL.md:140`
Evidence:
- Line 140 says a published change touches "an existing document only in its `status:` line", and that "designs … never ride it".
- Land pushes body edits to existing documents, keeping their status, including a capture's Solution ideas.
- Appending a sentence, as the Design says, leaves the bullet contradicting itself. AC5 only greps for `tracker.sh land`, so either version passes.
Recommendation: say in the Design that line 140's sentence is scoped to `tracker.sh`'s status publishes. For example: "a status publish changes an existing document only in its `status:` line. `tracker.sh land` pushes a capture's edits to draft backlog `<ID>.md` documents, with `design:` and `status:` unchanged, after a local full gate." Keep it one line, with `tracker-only` and `tracker.sh land` in it (RC7 and AC5).

Verdict: changes
