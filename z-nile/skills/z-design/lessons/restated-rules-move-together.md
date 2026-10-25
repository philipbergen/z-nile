---
title: Restated rules move together
when: design
tags: [stale-text, docs]
check: After changing a rule, does every place that restates it (AGENTS.md, other skills, the raft document, comments) still agree, and is the new wording pinned?
---
A rule is usually stated in one place and summarized in several others. A fix that changes the rule but not the summaries leaves an executor or a future agent reading the old rule.

**Why:** R0039's late rounds were mostly contradictions between the issue, the specs and the experiments. R0040 design review 2 (F5): round 1 split "every skill records lessons" into two forms, but the new AGENTS.md sentence still said every skill records them.

c0120 design review 002 F2: the design still named a superseded prototype commit, a `prototype.patch` "beside this document" that was never committed, and a 15/16 the Verification log had made 15/17. Pointers to prototype artifacts are restatements too.

c0120 code review 001 F3: the build's log named R0043 as the active raft holding the old paths; `./zn busy` said R0034 (the check log's tail had cut that line). A tool's answer copied into a document is a restatement: copy it from the tool's full output.

c0120 design review 005 F1: c0114's promoted `finished.spec` restated c0114's rewrite as a rule over the live tree; c0120 moved and rewrote those files again, and the override list missed it. A promoted spec is a restatement of its item's rule: when a design changes what the rule reads, list every promoted spec that reads it (measure, by running them on the prototype), and give each rule one owner.

**How to apply:** when a refute line changes a rule, grep the repo for its old wording and its key terms, update every restatement in the same change, and pin the new wording where a spec already reads that file.

R0044 design review 2 (F4): rounds 1 and 2 changed the design behind a separate chore (c0128), whose Problem still described the first prototype. When a design changes, update every document that explains it, including dependent chores, or say in the raft which of their words are stale.

c0115 design review 015 F2: round 014 fixed the engine's move-commit lookup (subject only, not `--grep`), and AC13's `check.sh` kept the old `--grep` for the same commit. When a lookup is fixed, search the item's own sequestered files (check.sh, experiments, specs) for the same mechanism in the same change.
