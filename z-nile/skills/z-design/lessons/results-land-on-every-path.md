---
title: A step's result needs a landing place on every path that runs it
when: both
tags: [dispatch, headless, outputs]
check: For each step a dispatcher, a CLI or a subagent can run, where does its result land on each path (interactive, dispatched, headless), and who reads it from there? Does any path say "return it" with no caller to return to?
---
A mode written for one caller ("return the review markdown; the lead writes the file") loses its result when another path runs it. A dispatched or headless run has no caller: its text ends with the process, and the spend line that follows names nothing.

**Why:** c0117 design review 007 F1: under the dispatcher a stream review ran headless, zz-review's Stream mode told the reviewer to return its text and write no file, the runner kept only the token count, and the dispatcher looked for review files in the issue's folder rather than the raft's. The review vanished, and its `record:` line named no file and no issue.

**How to apply:** for each mode, write down where its output lands on every path that runs it, and give each path its own carrier (here: the dispatched reviewer writes `stream-review-<issue>-NNN.md` itself in the raft's folder, an interactive subagent still returns text for the lead). Pin each path with a case that finds the output where it should be.

Inputs too (c0117 design review 008 F2): a step's inputs need a carrier on every path as much as its result. "The lead puts the previous round in the brief" has no brief under a dispatcher: the dispatched round-2 reviewer got no previous review or refute until its prompt named the files. For each input a mode names, ask who hands it over on the dispatched path.

Across hosts too (c0250 design review 003 F2, F3): "carried in git, read on any host" needs a carrier on the path where the local state is gone: a resume on another host, after a cleared `.cache`, or in a session that never ran the dispatcher. A design that copies the human's answer only into a local exchange delivers it only where that exchange still exists; pin a case that wipes the local state before the resume, and one for each way a step can start (the chain, a retry, a step started by hand).

Inferred targets and routes back (c0250 design review 004 F1 to F3): a default that infers which part of a bundle failed ("the lowest member still in `active/`") holds only on the path its author pictured; when the dispatched path and the hand path leave different state, make the caller name it. And between a stop and the resumed model step, list every step the chain runs (a script step such as `z-ready` changes what "ran last" means), and every item a step acts on that is not the chain's id (z-raft works on a draft raft from an issue's chain): each state keyed on "the item" says which item.

**Note** (f0421 design review 001 F13, 2026-11-24): a substituted review (a lower model, with consent) was recorded by one row, 'the spend path', but has four writers (`spend`, `commit`, a dispatched review, `idea`), and an approval given before the review does not change when its spend rows do, so 'the owner approves knowing it' held only when approval came second. The note was also undefined for the ids real rows carry (no effort, or an unplaced one). Check: does each writer of the record give the same result, one case each, and what does the result mean for the ids the data really holds?
