---
title: An Override list is confirmed by a suite run on a prototype, not by a grep
when: design
tags: [overrides, prototype, specs]
check: Was the list of promoted specs the change turns red confirmed by running the whole suite of every home, the slow tier included, on a prototype that holds every changed string and every later design revision, rather than by grepping for the text the author edits (specs pin rendered forms, derived strings and counts a grep for the source text does not match)?
---
A grep finds the specs that name the string being changed. A spec that pins its rendered form (a template filled with a project name, a digest, a count) names a different string and turns red unseen.

**Why:** c0239 design review 004 F1: the template's RC0 line became `--affected`, and `c0120/homes.spec` pins the rendered `... --project z-nile --full`, which no grep for `{{PROJECT}} --full` matched. The whole z-nile suite on the reviewer's prototype found it.

**How to apply:** build the prototype with every changed string and run every home's full suite once; each new red spec is an Override or a design change.

c0248 design review 001 F7 and F12 (2026-11-12): `z-nile/check.sh --affected` skips the measured slow tier, so a suite run that confirms the Overrides line must also run `z-nile/check.sh --slow`; watch-map and seven promoted folders went red only there, or only in the full set.

**Note (c0306's prep, 2026-11-14):** the suite run must be repeated after every design change to what a command writes, and it must include the slow tier. c0306's first prototype marked only the published `./zn new raft`, and `--slow` turned four promoted specs red. The revision also marked the local form (prep Q3: "every command that creates a raft"). The next `--slow` run turned eleven specs red, because every fixture that builds a raft offline and commits a hand-written review now meets the rule. For each place a new mark or rule is written, list the promoted specs that go through it, then confirm the list with the slow run.

**Also:** d0297 design review 001 F2: `Overrides: none` rested on the fast tier and 19 of the 97 slow-tier specs the change selects; 8 of those were red in the dispatched step on `main` as well, and one had no control. Run every slow-tier spec of the Affected list, with a control on `main` in the same environment, before writing `Overrides: none`.

**Note (c0304's prep, 2026-11-15, design review 001 F3):** c0304's E3 grepped for `c0045/workstreams` and the selector, and recorded "no other spec reads this file"; `c0060/retrofit` lists it as `tests/acceptance/c0045/workstreams.spec.luau` and scans its text, and its `watch.txt` does not name it, so neither `--affected` nor the item's check ran it. The grep with the basename (`workstreams.spec`) found it. For a Touched spec, every reader the basename grep finds goes in the Regression guard and in a check the item runs.

**Note (c0251's prep, 2026-11-15):** a promoted spec can pin a count, not only a shape. c0251's draft said the c0117 specs "stay green unchanged" because `order` and `specs` kept their meaning. But `c0117/models.spec` asserts `#models.tries == 4`, and the new Fable pool member makes it 5. Search the at-risk specs for counts (`#…==`, `toBe(<n>)`) over anything the change enlarges, as well as for the fields it changes.

**Note (c0210's prep, 2026-11-15):** `z-nile/check.sh --full` stops at the first project whose suite is red, so a known red spec on main (c0386's fence scan) hid every later home's results: the run read "1826 passed, 1 failed, 271 spec files", pickman's alone. When main carries a known red spec, run `z-nile/check.sh --full --project <name>` for each registered project (and `--slow`) and judge each by its own result line. And a prototype that moves a file must rewrite the watch files that name it, as `./zn commit` does in the raft; a plain `git mv` commit leaves them naming missing paths, which turns the selector's specs (c0114's gate-cover, c0120's graph-homes) red for a reason the raft will not have.
