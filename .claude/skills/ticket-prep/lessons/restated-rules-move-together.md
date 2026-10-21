---
title: Restated rules move together
when: design
tags: [stale-text, docs]
check: After changing a rule, does every place that restates it (AGENTS.md, other skills, the raft document, comments) still agree, and is the new wording pinned?
---
A rule is usually stated in one place and summarized in several others. A fix that changes the rule but not the summaries leaves an executor or a future agent reading the old rule.

**Why:** R0039's late rounds were mostly contradictions between the issue, the specs and the experiments. R0040 design review 2 (F5): round 1 split "every skill records lessons" into two forms, but the new AGENTS.md sentence still said every skill records them.

**How to apply:** when a refute line changes a rule, grep the repo for its old wording and its key terms, update every restatement in the same change, and pin the new wording where a spec already reads that file.
