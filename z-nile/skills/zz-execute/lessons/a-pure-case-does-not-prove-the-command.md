---
title: A pure case does not prove the command
when: both
tags: [specs, acceptance, commands, skills]
check: For each rule the Design delivers through a pure module, does a case run the real command (or read the skill text) that feeds it? For each new optional input field, does `grep` find a builder outside the specs that sets it? For each rule only the worker carries (a count, an order of steps), does the skill state it and a case pin the sentence?
---
A case that calls a pure function with its input already built passes whether or not any command builds that input. The same holds for a rule the engine leaves to the skill: the engine's half can be tested while the sentence that makes it happen is missing.

**Why:** R0129 code review 001 F1 and F3 (f0399, 2026-11-17). `raftplan.Issue` gained `deps`, and `plan.spec` passed with `deps` set by hand, while `./zn raft-plan` never filled it, so "a ticket and what it depends on go in one raft" did nothing in the real command. The design's release rule for a given-back draft and an empty `fix` was carried only by `--released`, which the skill never told the worker to count.

**How to apply:** when a design adds a field to a pure module's input, add one case that runs the command in a fixture and shows the field's effect in its output. When a design says "the skill carries it", write the sentence in the skill in the same step and pin it in a spec.
