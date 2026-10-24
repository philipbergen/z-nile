---
title: A bulk rename substitutes only the forms that name the thing
when: both
tags: [renames, migration, text]
check: Does every bulk substitution of a renamed name match only the forms that name it (a path through its old folder, a /command, "`x` skill", a known id), so that an ordinary word such as `tracker` or `architecture` in a path (`{root}/tracker`, `architecture.md`) is never rewritten, and was the diff read line by line?
---
Some old names are ordinary words that also appear in paths and code. A substitution of `/tracker` or `architecture` rewrites `{source}/tracker/…` fixture paths and `<root>/architecture.md` along with the skill names, and the specs that break look like unrelated failures.

**Why:** c0115 prep: the first substitution pass turned `{source}/tracker` into `{source}/zz-rules` in a dozen tooling specs and `{raft.root}/architecture.md` into `pickman-arch.md` in the engine. It was reverted and redone with slash commands limited to the hyphenated names, ordinary words only in "<word> skill" forms, and lesson ids only from the actual lesson list.

**How to apply:** list the forms each old name takes, substitute hyphenated (unambiguous) names freely and ordinary words only in their naming forms, take ids from the real list rather than a pattern, and review the whole diff outside the skill files before running anything.
