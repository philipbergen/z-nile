# Review 014: c0115 (design mode)
Inputs: prep-c0115 at 39cbeaac (`git diff 1c22dc9a 39cbeaac -- z-nile/.tracker/issues/c0115 .claude/skills`: c0115.md, freeze.spec, docs.spec, harvest.md, the zz-arch lesson); impl-c0115 at ca212954 (`git diff ff9a1401 ca212954 -- z-nile/engine z-nile/skills`: 6bffd681, d391e727); design-review-013.md and design-refute-013.md. Every experiment ran in a scratch clone (`scratchpad/review014/work`) whose origin is a bare copy (`origin.git`) holding the real remote's branches, with `impl-c0115` = ca212954 and `prep-c0115` = 39cbeaac. Nothing was pushed to the real remote.
Dropped from design-review-013: F2, F3, F4, F5 (fixed as the refute says; F2 and F5 carry the user's 2026-10-25 decisions). 013 F1's history rule is gone, but its replacement has the two holes in F1 and F2 below.

What holds:
- **Spec runs.** `lune run tests/run -- .tracker/issues/c0115/acceptance/freeze.spec.luau tests/acceptance/c0120/freeze.spec.luau tests/tooling/busy-holds-move.spec.luau` (from `z-nile/`) gives 16 passed, 0 failed.
- **c0120's specs keep their meaning.** Every busy call in c0120's two specs passes `{tracker, src, tests}`, `pickman/.tracker` or no paths at all (`grep -n 'busy(' …`). All of these lie inside c0120's new `paths` (`tracker`, `src`, `tests`, `pickman`), so no c0120 case now passes because the scope turned the freeze off.
- **The own-raft rule** matches the item between commas (`,c0115,`) in the raft document's `issues:` on origin/main. Only c0115's raft can list c0115, and a raft written in another `issues:` form simply blocks, which is the safe direction. Mutants A and B are killed by the new R0098/R0099 case, which I checked by reading it.
- **Scope normalization.** `./zn busy z-nile/skillsX` and `./zn busy .` leave the freeze off. `z-nile/skills/` and `.claude/skills/zz-x` leave it on. A path given from a subfolder (`skills`) leaves it off, which blocks: safe. The surviving gaps are in F4.
- **zz-rules' busy row** is general now and pinned by two docs.spec phrases (013 F3).
- **The new lesson** `zz-arch/history-tests-survive-squash` is a real lesson: another raft could make the same mistake, so it is more than a restated finding. Its "How to apply" needs one correction (F2).

### F1 [high] freeze.spec's squash case puts nothing under the move, so a pin that brings 013 F1 back passes it, and against today's remote it makes AC12 green
Where: `acceptance/freeze.spec.luau`, the first case ("main takes the prep's change as a squash"), and the G14 Rules and mutants row (mutants D and E).
Evidence: in the fixture, main squashes the prep and then `impl-c0115` is cut from **main**, so the move is the only commit in `origin/main..origin/impl-c0115`. The real branch is different: `git rev-list --count origin/main..6ae30bb2^` = 217 commits under the move, all of them c0120 and R0043 commits that main took as squashes. I tested a mutant in the scratch clone that replaces `c0115Move` with "the oldest commit of `origin/main..origin/impl-c0115`" (`rev-list --reverse`, first line). That is the "commit of the root that main doesn't have" test again, under the pin's name.
- c0115's freeze.spec: `6 passed, 0 failed`.
- Against the real branches, `./zn busy .claude/skills z-nile/skills pickman/skills` changes like this:
  - **unmutated:** it exits 1 on `origin/impl-c0120`, `origin/impl2-c0120`, `origin/prep-c0120` and `origin/proto-c0115`;
  - **mutant:** all four are `ignored for c0115's freeze: … (holds its move)` and nothing blocks. That pin (b33af7a8, `tracker: R0043 members`) is held by `origin/prep-c0120`.
- The mutant "pin = the tip of `origin/impl-c0115`" also survives (`6 passed`), because the move is that tip in the fixture.

013 F1's Recommendation asked for exactly this shape: "`impl-c0115` merges `stack`'s tip and then adds the move commit". The fixture skipped the merge.
Critique: mutants D and E prove that the history rule is off and that some pin exists. They don't prove the pin is the move. A wrong implementation passes AC12's spec and, on today's remote, AC12 itself (lesson zz-test/seed-every-enumerated-case: the fixture never seeds what the real branch has). The tempting fix is one more branch in the existing case. That fix only works if the branch holds a squashed commit that sits under the move.
Consequences: the fixture's `impl-c0115` must be built on a branch whose commits main took as a squash, as the real branch is. With that shape, the case that "a branch cut from the stack blocks" also kills mutant D for the right reason.
Recommendation:
- Rebuild the case's history:
  - `stack` holds commit s1, and main takes s1's change as a squash (`trackerfix.elsewhere`);
  - `impl-c0115` = `stack` + main merged + the move commit + one commit after it (i2).
- Assert all of the following:
  - a branch cut from `stack` that edits the skill paths blocks;
  - a branch cut from the move commit itself is ignored (`holds its move`);
  - a branch cut from i2 is ignored (`holds its move`);
  - a branch that holds s1 and the merge but not the move blocks.
- Add the two mutants above ("pin = oldest unmerged commit of the root", "pin = the root's tip") to the G14 row, and run them against the port.

### F2 [medium] The move commit is found by any message line, anywhere in impl-c0115's history (main's included), newest first. One commit on main whose body quotes the subject makes every branch cut from main "hold the move"
Where: `c0115Move` in `z-nile/engine/main.luau` (`git log -1 --format=%H --grep=^c0115: move the skills refs/remotes/origin/impl-c0115`); the FREEZES comment and G14's third bullet ("which AC13 pins as unique"); 013 refute F1.
Evidence:
- `--grep` matches any line of the message, not only the subject (`^` anchors each line). `-1` takes the newest match by date and hides every other match. The walk covers all of `origin/impl-c0115`'s history, origin/main's commits included.
- AC13's uniqueness check reads only `$base..HEAD` (check.sh:82), so "unique by AC13" doesn't cover the range the lookup reads.
- In the scratch clone:
  1. I pushed to main a commit `tracker: c0116 design (#120)` whose body has the line `c0115: move the skills (renames only), as its base.`;
  2. merged origin/main into `impl-c0115` (which step 5c does after every merge of main) and pushed;
  3. cut `rogue` from origin/main, adding `.claude/skills/zz-rogue/SKILL.md`.
- `./zn busy .claude/skills z-nile/skills pickman/skills` then prints `ignored for c0115's freeze: rogue (holds its move)`.
- After the same step, a query outside the skill folders (`z-nile/skills/../.tracker`) also ignored an unrelated `.tracker` branch as `holds its move`.
- `git log --all --grep='c0115: move the skills'` already finds three commits (6ae30bb2, eccd71a8, 78b69796). Only one is on impl-c0115 today.
Critique: 013 F1 recommended a pin recorded by sha, never one found by searching history (lesson zz-review/sequestration-reference-not-a-ref, "An anchor found by searching history is chosen by whoever commits next"). The refute replaced the sha with a history search but gave no reason. The search's range and its match are both wider than the AC13 rule it cites. The author of `impl-c0115` controls `FREEZES` anyway, so the threat is not the author. It is anyone whose commit reaches main and then impl-c0115 through a sync. Main's commit messages in this repo quote each other's subjects all the time.
Consequences: the lookup should read the range AC13 reads and match the subject only. That makes "unique by AC13" true. A second match, or none, has to block (lesson zz-arch/guard-no-is-explicit): nil, never "the newest". After c0115 lands, its mark is gone, so the narrower range changes nothing then. The lesson `history-tests-survive-squash` recommends "a unique subject" without bounding it, so it teaches this hole.
Recommendation:
- Read `git log --format='%H %s' refs/remotes/origin/main..refs/remotes/origin/impl-c0115`. Keep the lines whose subject starts with the plain text `c0115: move the skills` (plain prefix match). Return the sha only when exactly one line matches, else nil.
- Change the comment and G14's bullet to "the one commit of `origin/main..origin/impl-c0115` whose subject starts …".
- Add freeze.spec cases:
  - main gains a commit whose body (not its subject) has that line, and impl-c0115 merges main: a branch cut from main that edits the skill paths still blocks;
  - a second commit with the subject on impl-c0115: the stacked-by-move branch blocks.
- Add the mutants "match any line" and "newest of several" to the G14 row.
- Amend the lesson's "How to apply" to "a unique subject within the branch's own range (`origin/main..<branch>`), refused when it is not exactly one".
Lesson: zz-review/sequestration-reference-not-a-ref

### F3 [medium] AC12 is red today on four branches the design never names: c0115's own prototype and landed c0120's three branches
Where: Implementation step 1 ("`./zn busy …` prints nothing"); G14; the 013 refute's F1 consequences ("checked against the open branches (prep-/impl-/proto-c0116, c0117, c0118, c0121)").
Evidence: in the scratch clone, with impl-c0115 at ca212954 and every other branch as on the real remote, `./zn busy .claude/skills z-nile/skills pickman/skills` exits 1 with:
- `branch origin/impl-c0120 changes …`
- `branch origin/impl2-c0120 changes …`
- `branch origin/prep-c0120 changes …`
- `branch origin/proto-c0115 changes …`

Before round 13, the history rule ignored all four (013 F1's evidence names two of them). Dropping that rule exposed them. The refute checked only c0116 to c0121's branches. `proto-c0115` is c0115's own prototype, and G14 lists neither it nor c0120's leftovers.
Critique: an executor at step 1 meets a red AC12 with no instruction. Deleting branches, or adding a name to `approved`, is the user's call ("approved by name"), so the raft stops at its first step (lesson z-design/new-rules-migrate-existing-work: which existing work fails the new rule on the day it lands, and what does the design say it does?). The tempting fix is to add `proto-c0115` to `roots` quietly. That widens an exemption the user granted by name.
Consequences: c0120's three branches are finished work (c0120 landed as c5b436ca). `proto-c0115` is superseded by impl-c0115 (§11 (q)). Each one either goes away or is approved by name, and either way is a user decision.
Recommendation: escalate to the user, in the prep PR, with these options:
- (a) delete `impl-c0120`, `impl2-c0120`, `prep-c0120` and `proto-c0115` on origin before c0115 is readied;
- (b) approve some of them by name in c0115's `approved`, with a freeze.spec line each.

Record the decision in G14, and add to step 1 the current `./zn busy` output and what the executor does with each line.

### F4 [low] The path scope's normalization has no case for its two transformations or its prefix boundary, and `..` passes as "inside"
Where: `allInside` in `z-nile/engine/main.luau`; freeze.spec's "the freeze covers only the skill folders" case.
Evidence: run against c0115's freeze.spec in the scratch clone,
- the mutant `string.sub(n, 1, #top) == top` (no `/` boundary, so `z-nile/skillsX` counts as inside) gives `6 passed, 0 failed`;
- dropping the `^%./` strip also gives `6 passed`.

`./zn busy z-nile/skills/../.tracker` counts as inside, so the freeze turns on for a `.tracker` query: `origin/prep-c0116 (stacked on its prep)` is ignored there. Lesson zz-arch/guards-trust-only-origin asks for paths "validated (relative, no `..`)".
Critique: nobody calls busy with these paths today, which is why this is low. Still, the scope is a user decision (F5, "Scope to its paths"), and its edge is unpinned.
Consequences: refuse or turn off the freeze for any path with a `..` segment, or an absolute one. That direction is safe, because the call then blocks.
Recommendation: in `allInside`, treat a path with a `..` segment, or a leading `/`, as outside. Add busy calls to the scope case:
- `z-nile/skillsX` → off;
- `./z-nile/skills` → on;
- `z-nile/skills/../.tracker` → off.

Add the three mutants to the G14 row.

### F5 [low] Stale text: c0115.md's AC12 spec line still describes round 12's rule, and the freezesOn comment is split by a new comment
Where:
- c0115.md line 370: "`freeze.spec` :: c0115's prep and implementation, the stacked items, branches built on them and the approved prototypes are ignored …". This line doesn't mention the move commit, the squash case, the own raft or the scope case.
- `main.luau`: `freezesOn`'s comment ("… and origin/main still holds the move's mark. Without paths") now breaks mid-sentence into `allInside`'s comment, which sits between it and its function.

Evidence: quoted above.
Critique: the spec list is where an executor maps cases to criteria (lesson z-design/restated-rules-move-together).
Consequences: none.
Recommendation: rewrite line 370 to list the six cases. Move `allInside` (with its comment) above `freezesOn`'s comment.

Candidate lesson (for the lead): a pin found by a search (`--grep`, "the commit with subject X") is only as unique as the range it searches. Search the same range the uniqueness check reads (`origin/main..<branch>`), match the subject alone, and refuse anything but exactly one. Check: "Does this lookup read the same range, and the same field, as the rule that claims it is unique, and what does it return for zero or two matches?" (from F2; it extends zz-review/sequestration-reference-not-a-ref and corrects history-tests-survive-squash's "How to apply"). A second one, from F1: a fixture for "survives a squash" must put the squashed commits *under* the thing it pins, as the real branch has them. Check: "Does the fixture's branch hold what the real branch holds below the anchor?"

Verdict: changes
