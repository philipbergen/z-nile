---
title: Rulings reach every acting item
when: design
tags: [scope, coordination, process]
check: Before any sentence that says what the user decided (or that they have not), was the answer file (`.cache/dispatch/<id>/answered-<n>.md`, the item's Problem) read again just now, and for each part of the ruling, which item will carry it out and does that item's document on origin/main quote the ruling verbatim, in a `Scope decision (user, YYYY-MM-DD): "<their words>"` line?
---
A user's ruling is made in the item that asked, but it is often carried out by another one: the spec's own chore, a later raft, the item that owns the rule it changes. If the ruling lives only in the asking item's document, the acting item's prep reads its bare capture and is free to decide the opposite. And an answer can arrive while the prep runs: the user writes it into the answer file and the item's Problem, and a document written from an earlier read says "no answer".

**Why:** d0298 design review 001 F1. The prep read `answered-1.md` at 17:07, when it held only the question. The user appended their ruling at 17:08 ("Rewrite the spec that forbids features and defects in z-nile's root so all three types are allowed there") and added a `Scope decision` line to d0298's Problem. The draft carried that line into its commit and still said "Q1 got no answer" in its Non-goals, Solution and E5. It also left c0266, the chore that rewrites the spec, at its bare capture, so c0266's prep could have chosen the rename the user had just ruled out.

**How to apply:** Reread the answer file and the Problem before writing any sentence about a ruling, and search the draft for "unanswered", "no answer" and the question's number. For each part of the ruling, name the item that acts on it. If that item is not this one, land the verbatim `Scope decision` line on its Problem (a capture land may edit a backlog document's sections) in the same round, and make this item's `depends_on` and acceptance pin the outcome. Leave the consequences that the ruling raises for the acting item's prep to ask.
