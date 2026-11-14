---
title: Read a fact the document holds from the document at each commit, never from commit subjects
when: design
tags: [history, git, derive]
check: Which commands change this field (a status word, a `raft:` line), under which commit subjects (a squash titled by its PR, a raft's move of its members, a give-back), and is the field read from the document after each commit rather than from a subject pattern?
---
A fact that a document's own front matter holds (its status word, its raft) changes under whatever subject the commit that changed it has. A derivation that matches subjects sees only the commands whose subject it knew.

**Why:** c0280 design review 001 F1: "each status change" was read from `tracker: <id> <word>` subjects, which on main are only `preparing` (111) and `new` (22); `prepared` (a prep PR's squash), `active` (a ready) and a raft's moves of its members never printed (f0100 changed status ten times and `who` showed two).

**How to apply:** read the field from the document after each commit of the item's life (one batched `git cat-file --batch`), make an entry where it changed, and use the subject only to say what kind of change it was (an unblock is a change to `new` by a `tracker: <id> new` commit).
