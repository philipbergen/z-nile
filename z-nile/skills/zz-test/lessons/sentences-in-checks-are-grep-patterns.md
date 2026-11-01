---
title: Paths and sentences in a check.sh are written so every path scanner reads them right
when: design
tags: [acceptance, paths, scanners]
check: Have c0120's check-paths, c0120's finished.spec (on the item moved to done) and any scanner in flight been run on this check.sh, and does it name checkout paths only through `$ZN_ROOT` and expected sentences only as inline grep patterns that don't start with `(`?
---
Three scanners read every check.sh's command words as paths from its project's home: check-paths while the item is unfinished, finished.spec once it is done (with no Touched exemption), and any rewrite of them in flight. A sentence stored in a variable, or a command after `cd "$ZN_ROOT"`, has words they read as missing paths, and the gate goes red at the item's own `done` or when the rewrite lands.

**Why:** c0183 design review 003 F1: AC2's `cd "$ZN_ROOT" && ./zn` and AC6's sentences in variables passed check-paths (Touched exemptions) but failed finished.spec on a simulated done and c0141's prototype scanner. A round-2 `$T` workaround had treated one scanner only.

**How to apply:** name the checkout's files as `"$ZN_ROOT/<path>"`; write expected sentences as inline `grep -qF -- "<sentence>"` patterns (in a function when there are several), never starting with `(`; and run all three scanners on the prototype, with the item both unfinished and moved to done.
