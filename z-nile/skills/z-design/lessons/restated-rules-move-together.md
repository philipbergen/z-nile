---
title: Restated rules move together
when: design
tags: [stale-text, docs]
check: After changing a rule, does every place that restates it (AGENTS.md, other skills, the raft document, comments) still agree, and is the new wording pinned? And after a scope change, has every sweep of the earlier design's text (Non-goals, the Regression guard, game-design.md, the landing order, the experiments' preamble) been redone, by a search for the old non-goal's words and for "either order", and, where a sentence names CI as the backstop because a worktree lacks a property of the checkout, has the design given the local check that property, and, for a clone that runs the gate outside the repo, does its origin still point at this checkout or is the real git directory missing from the `PICKMAN_FENCE_REAL_GIT` value the gate inherits? When a refute answers "fixed" for a finding that named a sentence to change, does it search for that sentence and find it gone? And when a round's answer adds a failure path (a time limit, a fallback), have the earlier promises it contradicts been swept, not only the sentences the reviewer named?
---
A rule is usually stated in one place and summarized in several others. A fix that changes the rule but not the summaries leaves an executor or a future agent reading the old rule.

**Why:** R0039's late rounds were mostly contradictions between the issue, the specs and the experiments. R0040 design review 2 (F5): round 1 split "every skill records lessons" into two forms, but the new AGENTS.md sentence still said every skill records them. f0158 design review 002 F5: depends_on gained f0110 in round 1, but the implementation step, the Regression guard, E1 and the test plan's screen count still stated round 1's earlier state.

c0120 design review 002 F2: the design still named a superseded prototype commit, a `prototype.patch` "beside this document" that was never committed, and a 15/16 the Verification log had made 15/17. Pointers to prototype artifacts are restatements too.

c0120 code review 001 F3: the build's log named R0043 as the active raft holding the old paths; `./zn busy` said R0034 (the check log's tail had cut that line). A tool's answer copied into a document is a restatement: copy it from the tool's full output.

c0120 design review 005 F1: c0114's promoted `finished.spec` restated c0114's rewrite as a rule over the live tree; c0120 moved and rewrote those files again, and the override list missed it. A promoted spec is a restatement of its item's rule: when a design changes what the rule reads, list every promoted spec that reads it (measure, by running them on the prototype), and give each rule one owner.

**How to apply:** when a refute line changes a rule, grep the repo for its old wording and its key terms, update every restatement in the same change, and pin the new wording where a spec already reads that file.

R0044 design review 2 (F4): rounds 1 and 2 changed the design behind a separate chore (c0128), whose Problem still described the first prototype. When a design changes, update every document that explains it, including dependent chores, or say in the raft which of their words are stale.

c0115 design review 015 F2: round 014 fixed the engine's move-commit lookup (subject only, not `--grep`), and AC13's `check.sh` kept the old `--grep` for the same commit. When a lookup is fixed, search the item's own sequestered files (check.sh, experiments, specs) for the same mechanism in the same change.

c0118 design review 009 F1: a note added to a lesson's body restated a new rule, but the lesson's `check:` (the only line `./zn lessons` lists) still asked the old question. A note that changes what a lesson teaches updates its `check:` in the same change.

A scoping sentence covers only what it points at (c0117 design review 010 F1): "the names above are the interactive path's" left a section further down still stating the old rule unscoped. When a rule gains a second path, search the whole skill for the old rule's wording, not just the section you edited, and scope each hit.


c0172 design review 001 F2: deleting the word CI from Merging left zz-execute, the worktree paragraph, the raft template and the Linux bullet still telling the agent that CI is the final check. The worktree sentence existed because a worktree under the repo loads the main checkout's `.luaurc`. The local check has to be a clone whose parent directories are not a checkout of this repo, not a renamed sentence about the same worktree.

c0172 design review 002 F1: that clone, made with `git clone` of the local checkout, kept `origin` pointed at the checkout, and `pre-push` allows a push to a local directory that is absent from `PICKMAN_FENCE_REAL_GIT`. The procedure removes `origin` and appends this checkout's git directory to the variable the gate inherits.

**Also:** f0148 design review 002 F3, F4: round 1 changed Behaviour 5 but left the Edge cases' "the lobby stores the best instead", and game-design.md kept "(1 until f0148)" twice.

**Also:** f0148 design review 003 F3: round 2 bounded the lobby's write at 5 s, which made "a later arrival without a new pick starts on level 1" false when the write lands after the claim; the sentence was swept in round 3.

c0263 design review 006 F1, F9: a refute that says a spec was changed must paste the grep showing the changed line; two specs asserted opposite things about `merged` after a refute claimed one was fixed.

When a mechanism is replaced, its other copies are replaced too (c0263 design review 011 F2): round 3 moved the sync to settling records by item id, and remap kept the retired by-path rule; list every place that merges the same file and give them one routine.
