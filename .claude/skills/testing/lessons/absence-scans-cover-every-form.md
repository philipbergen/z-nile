---
title: An absence scan covers every form a renamed id takes
when: both
tags: [renames, specs, coverage]
check: For each renamed identifier, does some spec fail when one old occurrence is left in each kind of live file (skill text, code comment, ledger, a diagram node of any shape), without flagging look-alike paths?
---
A rename leaves its old name in more forms than the scan was written for: a lesson id in a comment, a node in another diagram shape, a path segment. A scan built from a word list misses the forms it didn't list, and widening the word list flags ordinary paths (`tracker/next`, `scripts/tracker/…`).

**Why:** c0115 design review 001 F1: `testing/no-vacuous-pass` left in a skill and `architecture/guards-trust-only-origin` in a code comment passed both absence specs and `lessons --check`, because the scan matched the five ordinary skill words only as `.claude/skills/<old>` or "<old> skill". F7: the README scan read only `["…"]` labels, so a node in another shape escaped it.

**How to apply:** filter by the new name's existence, not by a word list: an old token counts only where its renamed target exists (`<new>/<slug>.md`), and never after `/` or `.`. Scan every live file kind, and give the planted-text case one occurrence of each form plus the look-alikes it must leave alone. Where a format has several shapes (mermaid nodes), require the one shape the scan reads, or scan them all.
