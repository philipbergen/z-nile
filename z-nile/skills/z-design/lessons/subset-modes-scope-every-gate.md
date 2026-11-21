---
title: A command that gains a subset mode scopes every gate it runs, or says why one stays whole
when: design
tags: [scope, gates, partial, landing]
check: When the design adds a mode that acts on part of a set (a landing of some layers, a run over some members), has every check the command already makes over the whole set (approvals, guesses, contracts, checks, refusals, in every branch of the command) been listed, and is each either narrowed to the part or kept whole with the reason and a case that pins it?
---
A command written for a whole set loops over that set in several places, some added by other tickets after the design was first written. A subset mode that narrows only the loops the designer remembered leaves the rest still waiting on the whole set, so the subset can never act, and no case notices because the fixtures make every member pass every check.

**Why:** c0248 re-prep design review 002 F3: `./zn done <R> --through <issue>` lands the green layers below a block, but f0399's approval and guess checks in `done` (the branch for a raft readied with `Lands: approved`, the default for z-work and a person) still looped over every member, so an unapproved member above the block stopped the landing below it. The fixtures approve every member, so AC6 and AC7 passed.

**How to apply:** grep the command for every loop over the set's members (`for _, m in issues`, `store.members`) in all its branches, list each in the Design with "narrowed" or "whole, because", and give the subset mode a case where one member outside the subset fails each narrowed check.
