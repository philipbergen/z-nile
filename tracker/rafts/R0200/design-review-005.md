# Review 005: R0200 (design mode)
Inputs: worktree prep-publish-state-to-main at ef78339 (clean). Files read:
- `tracker/rafts/R0200/{R0200.md,check.sh}`, `design-review-001..004.md`, `design-refute-001..004.md`;
- `tracker/issues/c0510/{c0510.md,check.sh}`, `acceptance/{status,publish,commands}.spec.luau`, `replacements/*`, `experiments/{status.luau.txt,publish.luau.txt,prototype.patch,skills.patch}`;
- `scripts/tracker.sh`;
- the review, tracker, testing and ticket-prep skills;
- `main` at 3af8ddf: R0190/c0500 and its sequestered specs, R0180/c0490;
- `prep-check-isolation` (c0640) and `prep-tracker-hardening`, read only.

Dropped from review-004: F1, F2, F3, F4, F5, F6 and F7. Each fix holds, or follows a recorded user decision. Some fixes introduced the new gaps listed below.

All runs were made in a scratch clone outside the repository, with its own bare origin, and the clone was removed afterwards:
- **Prototype as instructed** (both modules, both patches, both replacements): `scripts/check.sh --full` gave 633 passed, 0 failed, in 103 spec files. `tracker.sh check c0510` gave 8/8 PASS, and the three c0510 specs gave 48 passed. This reproduces the author's numbers.
- **The same tree merged with `main` at 3af8ddf** (R0090 game code, a `c0140/publish.spec` change, the R0180 and R0190 preps): the full gate passed and AC1-AC8 passed.
- **c0500 (R0190 on `main`) together with c0510**: c0500's `prototype.diff` applies cleanly on top of the c0510 prototype. Its three sequestered specs gave 28/28, and c0510's specs gave 48/48. Without c0500's code, c0500's specs give 9 passed and 19 failed both with and without c0510, so c0510 breaks none of them.
- **Mutants**:
  - "design check only on the moved item, not on the raft's members": commands spec 23/23 pass (F2);
  - "writes seeded with `os.time()`, only `stamp` seeded from `/dev/urandom`": status and commands specs 34/34 pass (F3).

User decisions are not reopened: the prepared rewrites of promoted specs, a stamp on every write, c0510 before the repository fence, claims documented rather than checked, and in-flight preps landing first. F1 is about stating the third and fifth decisions against today's `main`.

### F1 [medium] Order & dependencies are out of date against `main`, so the one open handoff goes to the wrong raft
Where:
- R0200 Order & dependencies, bullets 1-3;
- R0200 Theme and Risks, where "repository-fence raft (R0190, c0640)" appears;
- c0510 Design, Skills: "corrected Conflicts and Landing text";
- `main` at 3af8ddf.

Evidence:
- **R0190 and R0180 are taken on `origin/main`.**
  - `3af8ddf tracker: prep R0190 Renumber step one (#33)` gives R0190 to c0500.
  - `7b925ac tracker: prep R0180 Beta poll transient errors (#32)` gives R0180 to c0490.
  - R0200 still says "Two preps hold R0190 today" and "R0180 is also held twice", and counts five open preps. `git worktree list` now shows three: check-isolation, publish-state-to-main and tracker-hardening.
  - The fence raft is still `R0190` in `prep-check-isolation` (3a03bf2), so it must take a new id.
  - "a handoff to the R0190 owner" now names the renumber raft, which has nothing to do with the fence. The handoff exists to make the fence exempt `publish.luau` and chain to a fixture's own `pre-push`. That change has not been made: c0640.md lines 108-109 still ban `GIT_INDEX_FILE`, `hooksPath` and `env -u`.
- **Unreserved issue ids, not only raft ids.** These issues exist only on prep branches; nothing on `origin/main` holds their ids:
  - c0640 is only on `prep-check-isolation`;
  - c0560 to c0630 are only on `prep-tracker-hardening`, whose R0180 is a template-only draft.

  Once c0510 lands, the first `new issue c` allocates c0560, because the union of local and origin ids tops out at c0550. Bullet 3 covers this case only for raft ids.
- **c0500 now overlaps c0510 in a sequestered spec, not only in code.** The code composes (run above). But c0500's `skill-doc.spec.luau` pins three things in the tracker skill:
  - the Conflicts bullet keeps `git fetch origin main` and `never renumber`;
  - the Numbering bullet keeps "`tracker.sh new` always picks the **next multiple of 10**".

  c0510's Design asks for "corrected Conflicts ... text", but `skills.patch` never touches Conflicts. An executor who follows the Design and rewrites Conflicts around `tracker.sh sync` breaks c0500. If c0500 lands first, its promoted spec turns c0510's AC4 red. If c0510 lands first, c0500 hits a sequestration stop. R0190's own Risks say to stop and ask the user if c0510 touches that bullet.
- The prep is three commits behind `main`, and E7 is recorded on 01395fc. The re-run above passed, but the documents still give the old base.

Critique: the tempting fix is to replace "R0190" with "the fence raft" everywhere. That alone leaves the unreserved issue ids and the Conflicts trap.

Consequences: the fence prep must renumber its raft id before it lands, and it must land before c0510 merges (decision 5). It must carry the exemption before that (decision 3). The documents should say this sequence, because it is now a precondition with a hard order.

Recommendation:
- Merge `origin/main`, re-run E7 there, and record the new base and counts.
- Rewrite Order & dependencies:
  - R0190 is c0500 (renumber) and R0180 is c0490 on `main`;
  - the fence raft (c0640, `prep-check-isolation`) and `prep-tracker-hardening` must renumber;
  - the order is: fence prep, updated with the exemption and the hook chaining, lands; then c0510 lands; then the fence executes;
  - add a line on c0500: the code composes, verified; c0510 leaves the Conflicts and Numbering bullets alone because c0500's spec pins them.
- Name the issue ids that live only on branches (c0560-c0640) under "renumber on a clash".
- In c0510, replace "corrected Conflicts and Landing text" with "Landing text (the Conflicts and Numbering bullets are untouched: c0500 pins them)".
- Address the handoff to the fence raft's owner by worktree name, not by id.

### F2 [medium] The carried `prepared` checks members' `design: ready`, but no case can tell
Where: `cmd.status` in `prototype.patch` (`if carried then ... store.readFront(localItem.doc).design ~= "ready"` inside the per-target loop); the Rules row "The carried `prepared` refuses unless the raft and its listed members are `design: ready`" (`run`, mutant "no design check"); `commands :: a move to prepared is carried ...` and `... a raft move follows the local member list ...`.

Evidence:
- The only refused-for-design case moves the lone issue c0240, so the moved item is itself the target.
- Every raft move readies all of its members first. The raft-move case claims `cnew` and readies it in the same step, before the move.
- With the check changed to `if carried and t == id then`, which checks only the raft's own design, the commands spec gives 23/23 pass.
- So ticket-prep can set `design: ready` on the raft, forget a member, and carry `prepared` onto a member whose design is still a draft. Those are exactly the two fields that review-004 F1's fix was meant to tie together. The mistake surfaces later, as `start`'s local design refusal, after the prep PR has merged, and then needs a second PR.

Critique: the tempting fix is to assert on the message only, which would still pass if the raft's design were the one checked.

Consequences: none beyond one more refusal step in an existing case.

Recommendation:
- In the raft-move case, after `trOk(cap, { "status", cnew, "preparing" })` and before `ready(cnew)`, run `status rz prepared`. Expect it to fail, with stderr naming `cnew` and `design: ready`, and with origin and every local document unchanged. Then ready `cnew` and continue.
- Add "only the moved item's design checked" to the row's mutants.

### F3 [medium] The `stamp` command proves only its own seeding, not the seeding that every write uses
Where:
- `cmd.stamp` and the `stamp()` helper in `prototype.patch`;
- `commands :: stamps from processes started together differ ...`;
- the Rules row "Stamps come from real entropy ..." (`run`, mutant "a time-based seed (`os.time()`)");
- c0510 Commands, which never describes `stamp`: it appears only inside the guard's parenthesis.

Evidence:
- Two changes together make the mutant:
  - the shared helper seeds with `math.randomseed(os.time())`;
  - `cmd.stamp` seeds itself from `entropy()` before calling the helper.

  With that mutant, the status and commands specs give 34/34 pass.
- The only multi-process assertion goes through `tracker.sh stamp`. The published stubs are checked for format only. So review-003 F1's original bug, two terminals writing the same phrase in the same second, can come back in `new`, `new raft`, `status` and `start` with every check green.
- The design gives `stamp` no interface: no arguments, output, guard status or "same helper" rule. An executor who re-derives it from the Design text alone has nothing that binds it to the write path.

Critique: the tempting fix is a spec that runs concurrent `new issue` processes. Publish races make the loser draw again, so that spec cannot see equal seeds (the reason `stamp` was added).

Consequences: the binding becomes a code-review rule, because no black-box case can see it.

Recommendation:
- Add a Commands bullet: "`stamp <state>` (read-only, diagnostics) prints `stamp(state)`. `stamp()` is the only function that makes a stamp. It seeds once per process from `entropy()`, and every write (`new issue`, `new raft`, `status`, `start`) calls it."
- Add a Rules row: "every write and `stamp` use the one `stamp()` helper". Mark it as a code-review row (`reasoned`), with the mutant "a second seeding site".

### F4 [low] Read-only list, usage and case names still disagree across code, docs and spec
Where: the Rules row "Every command that is not read-only ..."; the guard case in `commands.spec.luau`; `READ_ONLY` and `USAGE` in `prototype.patch`; tracker skill Worktrees rule 1 in `skills.patch`; the c0510 Test plan and Rules rows.
Evidence:
- **The read-only list.** The code exempts eight commands: `list`, `find`, `members`, `metrics`, `board`, `workstreams`, `promote-check` and `stamp`. c0510 Commands names the same eight.
  - The Rules row lists seven and says "the whole usage table minus" them. `stamp` is in the usage table, so by that wording it is guarded.
  - The spec probes the same seven, so neither guarding nor exempting `stamp` is pinned.
  - The 13 guarded commands (14 calls, with `new` twice) plus these 8 are exactly the 21 handlers, which is consistent. `launch` goes through the guarded `worktree`.
- **The tracker skill.** Worktrees rule 1 calls `status` (without a target) and `sync` "read-only tracker commands", but the code guards both. Its "The tracker enforces part of this" list omits `status <id> <to>`, which now refuses in the main checkout.
- **The usage text.** It offers `status ... move one (new|preparing|prepared|active)`, but `status <id> active` is always refused.
- **Case names** that do not exist in the specs:
  - Test plan: `stamps from separate processes differ ...`. The spec has `stamps from processes started together differ ...`.
  - Rules rows: `a claim made by this terminal can be resumed ...`. The spec has `a start that dies after its claim is resumed ...`.
  - Rules rows: `two stamps ...` and `status :: six transitions`.

Recommendation:
- Add `stamp` to the row's list and to the spec's read-only probes (`{ "stamp", "new" }`).
- Call `status` and `sync` "allowed" (not read-only) in Worktrees rule 1, and add `status <id> <to>` to the enforced list.
- Drop `active` from the usage text's targets.
- Align the four case names with the specs.

### F5 [low] Smaller stale or unreachable text
Where: R0200 Whole-raft design and Risks; the tracker skill's Cutover bullet; ticket-prep step 5.
Evidence:
- **R0200 lags the c0140 replacement.**
  - The module map says "tests/acceptance/c0041/ one promoted spec replaced" and "first step in six skills". In fact two specs are replaced, and seven skills change: five sync and two fetch.
  - The Risks bullet "A promoted spec changes" names only c0041.
- **The Cutover bullet is unreachable.** It lives in a skill that exists only after c0510 merges, yet it says "Land such preps before this one merges". It gives no instruction to a prep that is still open after the merge: land it, renumber on a clash, never stamp its members.
- **Step 5 fails offline.** ticket-prep step 5 runs `status <R-id> prepared` unconditionally, but `cmd.status` fails without publishing (`status needs an origin remote`). Under `PICKMAN_PUBLISH=0` the step is impossible. An unstamped raft then needs no carried move, but a stamped one stays `preparing`.

Recommendation:
- Update the module map and Risks to cover both replacements and seven skills.
- Reword Cutover: "A prep opened before c0510 merged: land it as soon as possible, renumber on a clash, and never stamp its members."
- Add to step 5: "with publishing off, skip this step (an item without `status:` derives `prepared` from `design: ready`); a raft that was already stamped needs publishing on for this step."

Verdict: changes
