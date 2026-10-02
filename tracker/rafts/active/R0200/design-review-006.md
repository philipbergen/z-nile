# Review 006: R0200 (design mode)
Inputs: worktree prep-publish-state-to-main at e788335 (clean). Files read:
- `tracker/rafts/R0200/{R0200.md,check.sh}`, `design-review-001..005.md`, `design-refute-001..005.md`;
- `tracker/issues/c0510/{c0510.md,check.sh}`, `acceptance/{status,publish,commands}.spec.luau`, `replacements/*`, `experiments/{status.luau.txt,publish.luau.txt,prototype.patch,skills.patch}`;
- `tracker/issues/c0500/acceptance/skill-doc.spec.luau` on this base;
- `prep-check-isolation` at 4df78fd (c0640, still R0190), read only.

Dropped from review-005: F1, F2, F3 and F5. Each fix holds:
- **F1**: R0200 now states the real ids, the order (fence prep with the exemption, then c0510, then the fence executes) and the open handoff. c0640 at 4df78fd still strips and bans `GIT_INDEX_FILE` and has no exemption, which matches the "open handoff" R0200 records. `skills.patch` leaves the Conflicts and Numbering bullets alone, as c0500's spec requires.
- **F2**: the new refusal step kills "only the moved item's design is checked".
- **F3**: the design now has a Commands bullet and a `reasoned` code-review row.
- **F5**: the module map, Risks, Cutover and ticket-prep step 5 are updated.

F4 is only partly fixed (see F2 below).

How I ran the prototype: in a scratch clone outside the repository, with its origin replaced by a fresh bare repository, the clone deleted afterwards.
- **Prototype as instructed** (both modules, both patches, both replacements): `scripts/check.sh --full` gave 744 passed, 0 failed, in 118 spec files. `scripts/tracker.sh check c0510` gave 8/8 PASS. This reproduces the author's numbers.
- **Mutants**, one at a time, prototype restored after each:
  - (a) the carried `prepared` checks `design: ready` on members and lone issues but skips the raft's own document (`if carried and (t ~= id or not store.isRaftId(id)) then`): commands spec 23/23 pass (F1);
  - (b) `stamp` removed from `READ_ONLY`, so it is guarded: commands and status specs 34/34 pass (F2).

User decisions are not reopened. Their consequences are stated in R0200: the prepared rewrites, a stamp on every write, c0510 before the fence (the handoff is open and named), claims documented, and in-flight preps landing first.

### F1 [low] The carried `prepared` never has its raft-design check exercised
Where:
- c0510 Rules row "The carried `prepared` refuses unless the raft and its listed members are `design: ready`" (`run`);
- `cmd.status` in `prototype.patch`, the `if carried then ... design ~= "ready"` branch;
- `commands :: a raft move follows the local member list ...`.

Evidence:
- Every case that carries a raft to `prepared` sets `design: ready` on the raft document first: `ready(doc)` in the raft-move case, and the loop in `a prepared raft starts once`.
- Mutant (a), which skips the check for the raft itself, passes 23/23.
- Downstream, nothing catches it either:
  - `start` (line ~820) and `prompt` (line ~1474) check only the members' `design:`;
  - only make-prompt's skill text checks the raft's.

  So a prep PR can land a raft that is `prepared` while its design is still `reviewed`, and the raft can be started.
- This is the mirror of review-005 F2: that fix pinned the members' check, not the raft's.

Critique: the gap is small, because ticket-prep step 5 sets both fields. But the row claims `run` for a half that no case can fail.

Consequences: none beyond one more refusal step in an existing case.

Recommendation:
- In the raft-move case, call `ready(doc)` only after one refused `status rz prepared`. The refusal's stderr must name `rz` and `design: ready`, and origin must be unchanged.
- Add "the raft's own design unchecked" to the row's mutants.

### F2 [low] `stamp` is still not among the spec's read-only probes, and one c0510 sentence is broken (partial repeat of review-005 F4)
Where:
- `commands :: a tracker command in a directory that lost its .git refuses ...`, the read-only probe list;
- c0510 Rules row "Every command that is not read-only ...", which says "8 read-only ones including `stamp`";
- `design-refute-005.md` F4, which says "the spec probes all eight";
- c0510 Commands, the "Repo-root guard" bullet.

Evidence:
- **The probes.** The spec probes seven commands: `list`, `find`, `members`, `metrics`, `board`, `workstreams` and `promote-check`. `stamp` is not among them, and `git diff ef78339 HEAD` shows the spec changed only in the F2 case.
- **Mutant (b) survives** (34/34), so neither exempting nor guarding `stamp` is pinned. The refutation and the Rules row both claim otherwise.
- **The broken sentence.** The guard bullet reads: "**Every command except the read-only ones** (`list`, ... eight handlers in all; not `prompt`, which can create a raft). The other 13 handlers, including `status` and `sync`, are guarded first compares `git rev-parse --show-toplevel` with `pwd -P` ...". The parenthesis closes the sentence early, and the next one has two main verbs, so the rule cannot be read as written.

Recommendation:
- Add `{ "stamp", "new" }` to the read-only probes, or correct the row and refute text to say seven are probed.
- Rewrite the bullet as two sentences: "The eight read-only handlers (...) are exempt; `prompt` is not, since it can create a raft. Every other handler (13, including `status` and `sync`) first compares `git rev-parse --show-toplevel` with `pwd -P` and refuses when they differ (...), whatever `PICKMAN_PUBLISH` says."

Verdict: approve
