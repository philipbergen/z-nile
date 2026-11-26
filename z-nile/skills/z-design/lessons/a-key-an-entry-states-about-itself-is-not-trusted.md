---
title: A key an entry states about itself is not the key a rank check trusts
when: design
tags: [catalog, authority, refusals]
check: Can a file the rule distrusts (a closer file, an unplaced id) state the key that the rank or consent check reads, and does a case try it?
from: f0421 code review 005 F3, 2026-11-24
---
If a check lets an entry say who it is (`family`), then the entry can borrow another entry's level. Decide the key from data the rule trusts (the catalog, the id), and keep the stated value for questions that do not grant anything.

**Why:** f0421 code review 005 F3 (2026-11-24): a stated `family` became the entry's key and nothing checked it. A closer file's `[clis.claude] ultra = [{ id = "claude-haiku-5-5-xhigh", family = "claude-fable-5-2" }]` loaded, and the final review resolved to Haiku. The same raise without `family` was refused. The design's own example (`gpt-5.5-high` beside `gpt-5.5-extra-high`) was refused with the wrong id named. The model-raises-need-consent rule was meant to stop exactly that raise.

**How to apply:** key a catalog entry by its lower-cased id, take `family` only in the one trusted file, and add a case for a closer file that states a family, a case for two ids of one family loading together, and a mutant that ignores the stated family.
