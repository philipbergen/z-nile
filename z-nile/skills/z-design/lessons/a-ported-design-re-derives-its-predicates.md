---
title: A ported design re-derives its predicates from current main
when: design
tags: [prototype, redesign, port]
check: For each predicate this design defines (held, refused, carried), does the code on current main define it the same way, in every caller?
---
Porting an old prototype onto a newer main fixes the hunks that conflict. A rule the design relies on can have changed in code the patch never touched, and then the port applies cleanly and is wrong.

**Why:** d0298 was designed on 2026-11-12 and ported on 2026-11-18. In between, f0399 made an approval count when only a guess was added after it, and `work next` had its own order of checks. The port carried only fully held approvals and left `work next` alone on a guess whose evidence was a raft with no approval at all; design review 002 found both (F1 high, F3), and a third writer of the step environment the first round had missed (F4).

**How to apply:** List the design's predicates and every caller of each on current main before porting. Give each branch that is new since the design a seeded case and a mutant. A guess about what another command "already does" needs a run on a fixture that has the state in question.
