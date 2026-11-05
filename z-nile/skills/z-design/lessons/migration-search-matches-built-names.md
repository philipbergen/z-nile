---
title: A migration search finds the names a spec builds from parts
when: design
tags: [migration, guards, specs]
check: Does the search for the names, paths or variables a new rule drops or moves also match the ones a spec assembles from parts (`"GIT_" .. "DIR"`, a path built in two pieces), because specs split guarded names to pass the guard scan, and are the specs it finds each run?
---
A sweep that greps for the literal name misses the specs that hide it on purpose: the repository's guard scan bans some literal names in specs, so specs assemble them by concatenation. A rule that drops or renames such a name then breaks those specs and no search finds them.

**Why:** c0123 design review 007 F2. The sweep of 65 specs searched for `PATH =`, runner and `zn` copies, `fence.sh` users and inline `ac.sh` calls. `tooling/tracker-review-guards` builds `"GIT_" .. "DIR"` (the scan bans the literal), hands it through the tracker forwarder and expects the engine to refuse; the new environment cleaner drops the name, and the case failed with a fix that fitted none of the five patterns.

**How to apply:** add to the migration search a pattern for names built from parts (`grep -rlE '"[A-Z][A-Z]+_" *\.\. *"[A-Z_]+"' <tests>`), paste the command and its hits in the Design (lesson zz-review/lists-paste-their-search), run every file it finds once, and add a pattern to the fixes for what they need (here: start the engine below the cleaner, as `zn` does).
