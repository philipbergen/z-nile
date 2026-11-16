---
title: A finding that is a hardening idea, a missing spec, a hypothetical or polish is not a ticket
when: both
tags: [review, findings, tickets, withdrawn, scope, backlog]
check: Is this finding a hardening idea, a "no spec covers X", a hypothetical about unlanded work, or polish, with no incident that happened twice and no ask from the user (if so, it is not worth a ticket: say so and move on)?
from: user ruling 2026-11-16, "appproved in full" (tracker cull of 66 z-nile backlog issues)
---
A review finding or a one-off incident becomes a ticket only when an incident happened twice or the user asked for it. A hardening idea, a "no spec covers X", a hypothetical about work that has not landed, and polish are noted in the review (or dropped) and not captured. When a finding like the withdrawn ones below comes up again, it is not raised again: say it was withdrawn by the user and move on.

**Why:** on 2026-11-16 the tracker held 371 opened issues against 147 closed, and about 60% of the opened ones came from review findings and one-off incidents. The user withdrew 66 of them ("appproved in full"), listed below, and merged 8 more into the ticket that already covered them (c0167 into c0132, c0241 into c0180, c0268 into c0267, c0299, c0368 and c0391 into c0369, d0303 into d0298, f0363 into c0286).

**How to apply:** before writing a finding as an issue, ask the check question. If it is one of the four kinds and no incident happened twice and the user did not ask, write one line in the review ("not worth a ticket: <kind>") and go on. A finding that matches a withdrawn id below (same guard, same gap, same wording) is a repeat: do not capture it again. If a withdrawn idea is hit by a real failure twice, capture it then, citing both incidents.


**Hardening ideas (a guard, fence or runner made stricter against a case that had not happened twice).**

- c0075 Specs run in a bubblewrap jail on Linux
- c0123 Fence trusts only its own ref guard hooks
- c0157 Gate contention and tripwire
- c0160 Check paths third project
- c0162 Spec runner checks its Lune version
- c0163 Conflict marker gate
- c0168 Sweep counts other runs
- c0195 Ref guard misses branch copy
- c0225 Sweeper misses exiting leftovers
- c0226 Trail cuts move and change
- c0227 History uses ids renamedin
- c0229 Tmp trees on fixture volume
- c0231 Hook refuses bare yes
- c0232 Hooks bounded by wall time
- c0242 Declare the slow whole-repo specs' inputs
- c0245 Capture matching ignores registry
- c0273 Home rule reads project jsonc
- c0288 C0260 spec stall limit holds under load
- c0301 Trace none claims and tests only tickets
- c0315 Scanner hang proof tests
- c0317 A takeover writes a provenance record
- c0335 A beat pins main's paths at one sha
- c0336 The bounded network wrapper's child has a lifeline
- c0337 netRun states its own timeout
- c0338 Beater remembers refused start

**No spec covers X (a test or watch for a path nobody had seen fail).**

- c0233 Selector finds digest pinning specs
- c0281 Board round rule spy pin
- c0310 Watch whole tree specs
- c0311 Dispatch fixtures real git
- c0340 Provenance fixture names its branch main
- c0341 Watch sees probe run subjects
- c0349 Slow tier row for commit land
- c0352 Spec env reaches the specs
- c0364 Roadmap spec watches readme
- c0367 Docs selector is the watch map
- c0378 Checkpaths reader three rules
- c0381 Checkpaths reader review edges
- c0382 Checkpaths reader final review edges
- c0387 Fence scan watch misses new specs
- d0353 Watch miss typed defect
- d0355 Dispatch env reaches fixture specs
- d0357 Affected folder args miss specs

**Hypotheticals about unlanded work (a conflict, gap or wording in a ticket, raft or design that has not been built).**

- c0305 The dispatcher waits on a cheap model
- c0307 Metrics show cost per model
- c0312 Dispatched review refuses before it runs
- c0313 zz-review states which challenges use the author's model
- c0318 The raft review judges the whole solution
- c0323 Cross prep conflicts c0250
- c0326 Name finish watch in review
- c0327 Readme worker stale after 330
- c0332 AGENTS.md names the review models
- c0370 C0180 meets c0258 help core
- c0373 Beta publish only for game pull requests
- c0375 Close superseded items
- d0344 Harvest after final review unfinishes
- d0345 Work next stuck on deferred review
- d0350 Work next done without trace check
- d0358 Dispatched claim memory stale
- d0360 Ready refuses depends cycles

**Polish (a name, a message, a lint or a reader edge with no incident behind it).**

- c0329 Check names the wrong failing criterion
- c0334 Design record differs on empty files
- c0346 Trace reads plain scope decision
- c0347 Trace cell names any case
- c0351 Restack names failing check
- c0361 Lesson merge carries notes
- c0376 Loops lint strings and witness
