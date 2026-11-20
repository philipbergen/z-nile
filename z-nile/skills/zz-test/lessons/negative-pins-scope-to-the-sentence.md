---
title: A negative pin is scoped to the sentence it guards
when: design
tags: [docs, pins, specs]
check: For each "the text no longer says X" or "this sentence names no X" a docs spec claims, does the check read only the sentence (or paragraph) it guards, so that the mutant (X added around the pinned words) fails it, while text the issue does not own (another skill's own wording on the same page) cannot?
---
A `says` pin checks a substring, so a sentence that keeps every pinned part and gains a forbidden one ("After the one review round, a finding still open …") still passes, and the row that claims to kill that mutant cannot. A file-wide `unsays` goes too far the other way: it fails on wording another issue owns on the same page.

**Why:** c0250 design review 003 F8 (re-prep, 2026-11-19): the rule "`review-exhausted` names no round count" was pinned only by substrings, and z-design and zz-execute keep their own one-round text, which c0250 does not own, so a global `unsays` was not an option either.

**How to apply:** cut the guarded sentence out of its line (from the previous ". " to the next) and assert the negative there, and list the mutant as text added inside that sentence.
