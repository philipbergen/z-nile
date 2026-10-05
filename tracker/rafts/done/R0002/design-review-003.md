# Review 003: R0002 (design mode)
Inputs: prep-c0005-scope @ 5f44f2c: R0002 doc + check.sh; c0005 doc, check.sh, acceptance/worktree.spec.luau; design-review-001/002 and design-refute-001/002; skills (review, tracker, execute-raft, make-issue, ticket-prep, make-prompt, testing, architecture, metrics), AGENTS.md, SETUP.md, tracker/templates/{prompt.md,raft/check.sh}, .claude/settings.json, .gitignore, .github/workflows/check.yml, scripts/tracker/{main,store}.luau, scripts/tracker.sh, scripts/hooks/*.sh, scripts/lib/ac.sh, scripts/check.sh, tests/run.luau, tests/acceptance/c0001 and (on main @ 61c6a64) tests/acceptance/c0043 and tests/tooling/metrics-rounds. Scratch git experiments ran only in the session scratchpad; nothing was written in the repo except this file.
Dropped from design-review-002 (the fixes are real in the design, spec and check.sh): F1 (spec:244-261), F3 (the `prep-<slug>` rule), F4 (prune first, plus spec:302), F5 (except the leftover in F4 below), F6, F7 (except the leftover in F4 below), F9, F10 (spec:180), F12 (spec:165), F13 (AC5 settings grep), F14 (Test plan says four; spec:214; spec:234). F2, F8 and F11 are repeated below because their fixes don't work as written.

### F1 [high] (repeat of design-review-002 F11) The Bootstrap for executing R0002 fails at its first two protocol steps
Where: R0002 "Order & dependencies", Bootstrap bullet; execute-raft Phase 0 steps 1-2 as inlined in R0002's prompt (today's text)
Evidence: the Bootstrap creates the branch by hand with `git -C <root> worktree add -b R0002-worktrees-by-default ../pickman-R0002 origin/main`, then says the executor runs `start`, and that "today's `start` would also work". It doesn't:
- `start` runs in Phase 0, before any code is written, so it is today's `cmd.start`, which calls `git switch -c R0002-worktrees-by-default` unconditionally (main.luau:269-270). The branch already exists, so it fails. Reproduced in the scratchpad on git 2.54: `fatal: a branch named 'R0002-worktrees-by-default' already exists`, rc=128. The "branch already current" path only exists after implementation step 1.
- Before `start`, the inlined execute-raft Phase 0 step 1 says `git switch main && git pull --ff-only`. In a linked worktree that fails because `main` is checked out in the root: reproduced, `fatal: 'main' is already used by worktree at '<root>'`, rc=128. The prompt's hard rule 2 and the whole of Phase 0 are the executor's binding protocol, and the Bootstrap doesn't say to skip or replace them.

A context-free executor therefore either stops on a failed first command or improvises (switching branches, recreating the worktree) in exactly the checkout-mutating way this raft exists to prevent.
Fix: make the Bootstrap work with today's code and say which protocol steps it replaces:
1. `git -C <root> fetch origin && git -C <root> worktree add --detach ../pickman-R0002 origin/main`. Detached, so no branch exists yet.
2. Launch the agent there.
3. Tell the executor: "Phase 0 step 1 is replaced by `scripts/check.sh --full` in this worktree (don't `git switch main`). Step 2 is today's `scripts/tracker.sh start R0002`, which creates the branch from the detached HEAD."

Re-run that sequence in a scratch clone to prove it.

### F2 [high] (repeat of design-review-002 F2) The designed id-collision handling can neither detect nor resolve the collision it targets
Where: c0005 Design, "The worktree rule" 3.0 (landing step 0), `store.luau` paragraph, Usability; tracker skill "Conflicts"; `cmd.renumber` (main.luau:215-250)
Evidence:
- **Resolution is impossible after the merge.** Step 0 merges `origin/main` first, then says to "`tracker.sh renumber` yours". By then the two items share one directory (E7) and one `check.sh`, and for preps also one `acceptance/`. `renumber` can't separate them:
  - Under the design, `renumber` calls `store.get(old)` → `store.find(old)`, which now errors `duplicate id`. So the command meant to fix the duplicate dies on it.
  - Without the new error (today's code) it is worse. Scratchpad run on a clone of this branch: `new issue c alpha` gave `c0044/c0044-alpha.md`, and I added `c0044-beta.md` beside it. `renumber c0044 c9991` then exited 0, moved the *whole* directory, renamed only the alpha doc, and rewrote `id:` in both docs: `tracker/issues/c9991/{c0044-beta.md, c9991-alpha.md, check.sh}`, both with `id: c9991`. The global reference rewrite (`walk(store.ROOT)`) also renames every mention of the other item's id.
  - The same applies to "same id in two state directories": `walk` rewrites both items' references.
- **Detection isn't wired in.** Step 0's detector is "run `scripts/check.sh --full` … if `store.find` reports `duplicate id`". But `scripts/check.sh` never calls the tracker on the real tree: its only tracker mentions are the lint dirs (check.sh:24). No spec in `tests/` reads the real `tracker/` through `store`: the c0001 and c0005 specs use their own fixture trackers. CI runs the same gate. So for a capture or prep landing (no `done`, no `members`), nothing in the procedure or in the Merging conditions ever calls `store.find`, and the colliding PR merges green.

AC7 tests only the error message, not the documented recovery, so the spec can't catch this.
Fix: resolve before merging, and detect with a real command.
- Rewrite landing step 0: `git fetch origin main`. For each item id your branch adds (`git diff --name-only --diff-filter=A origin/main...HEAD -- tracker/`), if `git ls-tree -r --name-only origin/main tracker/` already has that id in any state directory, run `tracker.sh renumber <id> <next free>` on your branch *before* `git merge origin/main`. Then run `scripts/tracker.sh list >/dev/null` (it must succeed) and the full gate.
- Update the tracker skill's "Conflicts" rule the same way.
- Optionally make the detector unconditional: a `tests/meta` spec, or a gate line, that runs `store.all` over the real tracker.
- Add a spec case: two worktrees each `new issue`, one lands, the other follows step 0 and ends with two distinct ids and `list` succeeding.

### F3 [medium] (repeat of design-review-002 F8) JC1's Pass clause contradicts the rule-1 whitelist, so JC1 still can't be ruled consistently
Where: c0005 JC1 Pass; Design rule 1 (whitelist)
Evidence: rule 1 whitelists two commands that run a gate in the main checkout:
- `scripts/setup.sh`, whose last stage is `scripts/check.sh --full` (SETUP.md step 4, and SETUP.md:5-8 runs it right after `git clone … && cd pickman`);
- `tracker.sh check`, whose raft `check.sh` runs `scripts/check.sh --full` as RC0 (tracker/templates/raft/check.sh).

JC1 Pass then additionally requires that "every instruction that edits, stages, commits, switches branches **or runs a gate** does so in a worktree". So SETUP.md's bootstrap line fails JC1 under the second clause and passes it under the first. A strict round-3 code reviewer who quotes SETUP.md:7 blocks the merge (execute-raft Phase 4 step 7), and a lenient one can wave through anything. The rubric is still not decidable.
Fix: drop "or runs a gate" from the Pass clause. The whitelist is the single test: "every command the named documents run in the main checkout is on rule 1's whitelist, and nothing else in them edits, stages, commits or switches branches there; quote any line that isn't". Alternatively, remove `check` from the whitelist and say setup's gate is the one exception.

### F4 [medium] Documents the Docs list leaves untouched still say `prompt <issue>` wraps a raftless issue, contradicting make-prompt's new rule (a JC1 "two documents disagree" failure)
Where: c0005 Docs list (make-prompt, tracker skill bullets); `.claude/skills/tracker/SKILL.md:36`; `.claude/skills/make-prompt/SKILL.md:3` (frontmatter description); `scripts/tracker/main.luau:255` (start's error text)
Evidence: the design makes make-prompt never create a raft ("a raftless issue goes back to ticket-prep"), and `prompt` refuses to create one in the main checkout. These still say the opposite, and none of them is named in the Docs list or caught by AC5's grep:
- tracker skill:36: "Running a single issue means wrapping it in a placeholder raft …; `tracker.sh prompt <issue>` does this automatically."
- make-prompt description: "for a raft (or a single issue, which gets a placeholder raft)". This is the text the harness uses to trigger the skill.
- `start`'s failure message: "wrap a single issue with `prompt <issue>` or `new raft ... --single`".

An executor edits what the Docs list names. JC1 Fail includes "two documents that disagree about the procedure", so this surfaces only at code review, as rework, or as a round-3 blocker.
Fix: add three bullets to the Docs list. tracker:36 becomes "…wrap it with `new raft … --single` in ticket-prep". The make-prompt description drops the placeholder clause. `start`'s message names ticket-prep. Add `-e "does this automatically"` and `-e "which gets a placeholder raft"` to AC5's negative grep.

### F5 [medium] The prep is based on pre-R0007 main: c0005 lacks the now-mandatory Rules and mutants table, and R0002 says R0007 is still in flight
Where: R0002 "Order & dependencies" ("R0007 (review second order, in flight)"); c0005 Test plan; branch base 1d9a5d1 vs main 61c6a64
Evidence: main has merged R0007 (61c6a64, "R0007: Review second order (#8)"). On main:
- ticket-prep §3 requires a "Rules and mutants" table in every issue (one row per behavioural rule, with `run`/`reasoned`), and `tracker/templates/issue/doc.md` carries it. c0005 has no such section.
- review design-mode item 0 audits that table, so no reviewer on main can complete a design review of c0005 as it stands.
- design-refute lines take the form `fixed: <what>; consequences: <…>`.
- The review format replaces `Fix:` with Critique/Consequences/Recommendation. This file follows the Where/Evidence/Fix format I was instructed to use.
- R0007 also added 20 lines to `scripts/tracker/main.luau`, one of this raft's touched files.

The prep PR must merge origin/main anyway (the design's own landing step 0). After that merge, c0005 is non-conforming, and R0002's "whoever merges second rebases" note is stale.
Fix: merge origin/main into the prep branch now. Add c0005's Rules and mutants table: the ten E6 planted mistakes are already `run` rows. Add `reasoned` rows for the rules without a mutant case: the `renumber`/`prompt` guards, `done`'s `onGitHub` gating, and the 40-character cap. Update the R0002 note to "R0007 has merged".

### F6 [low] Loose ends in names, lookups and records
Where: c0005 `cmd.worktree` steps 1-2 and 5; R0002 "Experiments phase"
Evidence:
- The name cap of 40 characters rejects a real capture name. This repo's longest issue slug, `check-affected-empty-array-bash32`, gives `capture-check-affected-empty-array-bash32` (41 characters), so make-issue's first command fails with `invalid worktree name` and nothing says to shorten the slug.
- Raft targets are looked up with `store.get` in the *invoking* tree. From a main checkout that hasn't been pulled since the prep PR merged, `worktree R0008` fails with `no such tracker item`, and a raft that is done only on `origin/main` isn't refused. The branch-exists path also uses a stale local branch rather than fast-forwarding it to `origin/<branch>`.
- R0002 says E6 caught "four planted mistakes", but c0005's Verification log records ten.
Fix: raise the cap to 64, or have make-issue say to shorten the slug. Have `worktree` read the raft from `origin/main` (`git ls-tree` over `tracker/rafts`), or state that the main checkout must be pulled first. Sync R0002's E6 sentence with the log.

### F7 [low] Promoted-spec couplings and small coverage gaps
Where: worktree.spec.luau:380-394; c0005 AC6 and the `refuseInMainCheckout` callers
Evidence:
- "post-edit hook lints with the edited file's worktree config" depends on the committed `selene.toml` containing the literal `unused_variable = "deny"` (`edit` asserts the pattern). Once the spec is promoted, it runs in every raft's gate, and any later chore that reformats or relaxes that line fails c0005's spec with `pattern … not found`, far from the change.
- The design guards `renumber` and a raft-creating `prompt` too, but no case exercises either. An implementation that guards only `new` and `start` passes.
Fix: have the case write its own minimal `selene.toml` into both trees (`std = "roblox"`, deny in the main checkout, allow in wt2) instead of editing the repo's. Extend "start and new are refused in the main checkout" with `renumber f0020 f0021` and `prompt f0050` on a raftless issue added to the fixture seed, each refused and leaving `status --porcelain` empty.

Verdict: changes
