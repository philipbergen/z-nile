---
title: A rule decided for one item's check stays in that check's call
when: both
tags: [scope, commands, exemptions]
check: Does this exemption change the command's answer for callers the decision didn't name (other arguments, other commands that share the logic, after the item lands)? Is it applied only for the call the decision names, with an end condition that turns it off by itself, and is what it skipped still shown somewhere?
---
A user decision that exempts something for one item's check (a freeze, a gate, a readiness test) is about that check. Put into a general command for every caller, it silently changes the command's answer for callers nobody asked about, and it outlives the item: a later branch that reuses an exempt name is exempt too.

**Why:** c0120 code review 011 F1: the user exempted the branches stacked on c0120's prep, and five approved by name, from c0120's freeze (AC16, `./zn busy tracker src tests`). The exemption went into `./zn busy` for every path set, so with no paths (compaction's set) busy printed nothing while `./zn compact` refused on six branches, and the zz-rules skill's `busy` row was false. The names were fixed in the engine with no end condition.

**How to apply:** apply the exemption only for the call the decision names (here: explicit paths), and only until the item lands, read from a fact that changes when it does (here: `origin/main` still holds the old layout's mark). Name each skipped thing on stderr, uncounted, so the answer stays honest. Add a case for each boundary (another caller, after landing) with a mutant that drops it.

An exemption follows from what the item is, not from what a PR says about it (R0052 code review 001 F1): the rafting gate exempted the sequestered files of every issue a PR listed in a raft's `issues:`, so a PR chose its own exemptions by listing a member and rewrote that member's reviewed `check.sh` to `exit 0`. Keep the set of items a PR may carry apart from the set whose sequestered files may change; a prepared issue's are never a rafting PR's to change.

A set of exempt items is derived from the base, never from the change being judged (R0052 code review 002 F1): after 001's fix the rafting gate still exempted every raft whose document the PR touched, active ones included, and let a raft's `issues:` line make any issue carry-able. A PR that can name a raft or an issue in its own files chooses its exemptions; read each item's state and membership from main.

An exemption granted per item still lets the change rewrite the item (R0052 code review 003 F1): after 002's fix an issue joined the carry-able set by the `raft:` line in the PR's own version, so a PR moved an active raft's member out and rewrote its design. Judge an existing item's change by its shape against the base (which lines may differ, in which folder, between which values), not only by whose item it is.

An allowance for 'any file of item X' includes the file that makes X an item: a carried item keeps its identity file at the head (R0052 code review 005 F2). Check: can the PR delete, rename or omit the file the tracker's reader finds the item by?
