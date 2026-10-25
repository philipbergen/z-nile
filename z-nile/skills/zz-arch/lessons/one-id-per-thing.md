---
title: The same thing gets the same id from every source a merge reads
when: design
tags: [merge, dedupe, concurrency, data]
check: For each source that can add an entry to a merged collection, can it offer something already offered under another id (or with a placeholder sort value), and what happens when the other source's write lands first?
---
A merge that dedupes by id is only correct if one real thing has one id, whichever source offers it. An id derived from a thing's values (a score and a level), or a placeholder sort value (a date of 0 for imported data), gives the same thing a second identity, or a wrong place in the order, as soon as two writers can see it in different orders.

**Why:** R0044 design review 2 (F1, F2): the all-time list merged per-player bests as `best:<user>:<score>:<level>` at 0. Another server's write could merge a run's new best before the run's own write landed, so the run was listed twice and heard one place low. A run cut from the list came back as its best dated 0 and won ties it had lost. The fix stored the run's id and instant on the per-player row, so every source names the run the same way.

**How to apply:** when a merged structure takes entries from more than one source, give each entry its identity where it is first written and carry it through every copy. Keep a derived id or placeholder only for data that truly predates the structure, and say why it is right there.

R0044 design review 3 (F1, F2): the fix named each run on its companion row, but took the best's score from the ordered store, so a half-written or cached row joined one run's id to another write's score, and "the stored copy wins" kept it. And the round-1 rule that skipped a best "covered" by a listed run of its player was itself a value-derived identity, and it hid real runs. An id names one thing only if every field travelling with it comes from the same atomic write; dedupe by that id and nothing else.
