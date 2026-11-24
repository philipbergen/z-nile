---
title: A builder runs every static step and guard spec before it reports
when: build
tags: [builder, gate, static, guards]
check: Does the brief for a builder name the type check (the luau-lsp analyze step as check.sh runs it), the watch check, and the repository-wide guard specs (loops, cache paths, the fence, the gate queue) as things to run before reporting, beside the formatter and the linter?
from: full gates of f0421-can, f0437-approvals, d0434-restack and c0435-easy-path, 2026-11-22 (#754 to #757)
---
A builder runs what its brief lists. The gate stops at the first static step it fails, so each one missed costs a full round trip to the lead.

**Why:** 2026-11-22: four branches in one day failed the lead's full gate on things no builder had run: the type checker (three branches), an unsorted watch file, the loop guard (two branches), the cache-path list and the fence guard. Every brief had named only the formatter and the linter. Each trip cost a gate run and a message to the builder.

**How to apply:** the brief lists the steps by name: stylua, selene, the analyze step exactly as check.sh runs it, watch-check, zn --help, and the guard specs scanning-loops, c0193 tree, c0077 cache-paths, repo-fence and gatequeue, then the affected set chosen by the affected command, not by hand.
