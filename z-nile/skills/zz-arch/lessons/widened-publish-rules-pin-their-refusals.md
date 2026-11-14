---
title: A widened publish rule pins what it still refuses
when: design
tags: [publish, guards, specs]
check: For each new kind of commit the publish guard accepts, is the accepted edit stated line by line (which lines, which items, which sections), and does a spec drive each refusal that still applies inside that commit?
---
A rule written as "strip these keys and lines, then compare" accepts far more than the design lists: rewritten lines, moved lines, edits to other items in the same commit. Without refusal cases, the mutant "accept anything" survives.

**Why:** c0250 design review 001 F9: the block and resolve rule stripped every Decided and Scope line and six front-matter keys from every document in the commit, and no case drove a refusal.

**How to apply:** compare against the origin text keeping every origin line in order, list the added lines' shapes and where they may sit, limit front-matter edits to the items the decision touches, and write a pure spec over the guard with one refusal per row.

**Note (c0250's prep, 2026-11-13):** let the rule find the item from the commit itself (the item is the one whose note the commit writes, its members the issues its document lists on origin), rather than from a new argument the caller passes: a caller can pass the wrong id, the commit cannot.

**Note (c0250's prep, mutant re-run, 2026-11-13):** the command's own spec pins where each added line sits too, not only the guard's spec: with the guard's check off, a Scope line appended outside `## Problem` passed the `split` case, which only asserted that the line existed. Assert each added line with its neighbours (the next heading after it).
