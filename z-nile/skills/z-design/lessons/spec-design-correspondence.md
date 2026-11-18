---
title: Specs and Design correspond one to one
when: design
tags: [acceptance, rules-and-mutants]
check: Does every behaviour the Design states have a spec case that fails without it, does every sequestered assertion follow from a Design sentence, and does every check's label say exactly what its command verifies? Is each new case's recorded mutant killed by that case itself, not first by an older, stricter case (delete the case: does its row's mutant still die)? Does every outcome stated under Edge cases (not only under Behaviour) have its row and case too And does every destination or outcome the Design states for a rare input (a file name, a path it lands in) have a row, or is the claim dropped with the reason it is no rule? And does every Guess (pending user) line describe what the Design builds and its specs pin, so the user rules on what will be built?
---
Sequestered specs and the Design must match in both directions. A stated behaviour with no failing case (a refusal, an output format, an order) can be implemented wrong. An assertion the Design never states (message wording, which stream) can fail a correct implementation that the executor may not fix.

**Why:** R0040 design review 1: F3 found four specified CLI behaviours with no case; F6 found assertions on unspecified message text and on the output stream; F9 found an exit check whose label promised more than its command checked.

**How to apply:** walk the Design sentence by sentence against the Rules table, then walk each spec assertion back to a sentence. Specify every message shape and stream that a spec reads. For specs that read prose (skill text), quote the exact sentences in the Design, then trace mechanically: every literal the spec searches for must appear in the Design or in the file as it is on `main` (R0040 design review 4, F3: four pinned phrases were only paraphrased in the Design).

R0044 design review 4 (F1): the Design said the `UpdateAsync` transform keeps the place of its last call, but both stubs ran the transform once, so no case could fail it. A stub of an engine call that may retry its own callback must be able to call it again on a changed value.

**Note** (f0146 design review 001 F2): a decision recorded with the user is a stated behaviour like any other. "The first controller only" had no case, and the design built something else (every controller's buttons acted). Give every decided guess a case that fails on its plausible mutant, and check the design really builds what the decision says.

f0126 design review 011 F3: V9 (the gold moved near Inky) was killed first by the exact-gold case, so the record never showed the new CIE76 case could fail; the row now mutates Inky instead, which only the new case catches.

c0153 design review 002 F1, F2: `plain.roundTrip` "checks plain data, then compares the decoded value", and every case that reached the comparison expected `true`, so a `roundTrip` that compared `v` with itself, or returned `true` after the check, passed; and "a table reached twice is not a cycle" had no case, so a `seen` set never cleared passed. For each function whose cases all expect success at a step the Design names, add an input where the intended code fails at exactly that step (here `eps` 0 on the one-ulp value), and a case for each "is not" the Design states.

c0180 design review 004 F1: a round added a field (`clean`/`edited`) to a record format and changed one case's hand-written line to `edited`, while another case still expected the other worktree to count that line; only a wrong, asymmetric reader passed both. When a round adds a field or rule to a format that existing cases write, re-read every case that writes or reads it, from each side (this worktree and a sibling).

Disk, not index (c0263 design review 010 F1): a case that pins "nothing at the old place" after a merge must read the disk the way the engine does (a folder scan, `./zn find`), not only `ls-files` or `git status`: a record unlinked but its folder left made every later command fail with "duplicate id" while the case stayed green.
c0264 design review 005 F2 and 006 F2: vocabulary pins were chosen by what looked important, and rules the Design lists (expensive models on final reviews, the idea review, the order working around blocked items, lost work first even when a person started it, the full-force review fresh) had none; five mutants passed. Derive the pins from the Design's list of rules, one phrase and one deletion mutant each; and when a decision becomes "the text says no X", add a mutant that puts X back where the decision applies.

c0260 design reviews 006 and 007: beside every refusal case add one where the accepted kind of document passes through the same command; an audit rule that runs on every tree needs a case where the everyday states pass clean (a fresh stub at draft, an agent-filed ticket, a finished item).

**Also:** c0279 design review 002 F3: a Rules row's mutant has to die because of that row's rule: the row for the silent hold after a stop named a mutant (the stop replaced by `true`, no marker) that fails with or without the hold. Weaken the rule's mechanism (the hold from 120 s to 20 s) and check that the row's mutant then survives; if it still dies, it tests something else.
Note (c0246 round 7): when a function's answer gains a value (a boolean becomes "nested" | "link" | nil), re-derive each row's mutant for the new value, and make a fixture that must stay clean assert no line at all, not only the absence of one line.

Note (d0331 design review 001 F1, F4): a decision tested only as a pure function is not tested at the command. Each value of each input the caller computes (main moved, bases put back, the attempt) needs a case through the command, or a caller that hard-codes one input passes. And a criterion whose check runs a whole spec file is only as narrow as the file: run a fixture spec once with `--out` and let each criterion name its own cases.

c0302 design review 001 F5: a Non-goal ("mainTip keeps its refusal") was a rule with no Rules row, and the spec the Design cited for it had never existed. The design's own rejected option passed every check. A Non-goal that says existing behaviour stays names the spec that pins it, checked with `ls`, or adds one.

c0270 design review 001 F4: the sentences that decide whether a hit stops the session (yours, "or none", "a merged one is history") had no needle, so four plausible rewrites passed every case. The classification is the rule: pin each sentence.

**Also:** f0201 design review 001 F1: the Design said the record seen is refreshed by "every read and write, a grant here included", but no case followed a grant with the read or use that depends on it, and deleting the refresh passed all 88 cases; each writer of a cache, and each exclusion, gets a case that reads after it. F12: twelve stated rules had a case but no row; walk the Design sentence by sentence against the table before the review.

c0273 design review 001 F4: the Design said a `default.project.jsonc` builds into `check.rbxl`, with no row or case; the home rule refuses every home holding one, so the claim was dropped and the reason recorded.

**Note** (R0109 final review 001 F3): a pin of an order that already held in the text it replaced cannot fail when the new sentence is deleted. The first case of `trace-skeleton.spec` found "skeleton" before "final review" in the old Phase 5 step 3, which says "print the trace skeleton" and then "run the final review" and never commits the skeleton. Pin the new sentence, and build a prompt with the function that writes it (`dispatch.prompt`) rather than searching the source file, where the sentence can hide in a comment or another mode.

- f0208 design review 001 F4: the tenth Guess said a failure's note clears after Travel's 3 s cool-down, but nothing cleared it and failures outside Travel had no cool-down; the user would have ruled on text that was not built. The Guess is now the rule the server implements (a 3 s rest, then idle), with its cases.

**Also:** f0399 design review 001 F8 and F11 (2026-11-16): the capture named "material change" beside "guess", and only the guess had a rule and a case; and the pure spec pinned fields and functions (`blockOn`, `onLanded`, `work.baseFor`) that only the prototype defined. After prototyping, copy the prototype's exported types and signatures into the Design, and give each captured noun its own row.

**Note** (R0125 code review 001 F1, fixed as d0412): f0145's rule "a decline during the write is applied after it" had one case, a write that used a revive (given back); c0202 carried it over. A write can answer three ways (used, none held, cannot tell), and only the first applied the decline: the other two opened the revive's purchase screen after the player declined. A rule about an event inside a call gets a case for every answer that call can give.
