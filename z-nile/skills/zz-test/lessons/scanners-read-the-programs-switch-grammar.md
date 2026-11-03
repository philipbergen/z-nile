---
title: A command scanner reads the program's switch grammar
when: build
tags: [hooks, scanners, parsing]
check: For each program flag a rule keys on, do the bundled (`-we`), attached (`-e'code'`) and value-taking (`-I dir`, `-M mod`) forms reach the same verdict, and is each in a case?
---
A rule that matches one exact switch (`-e`) misses every other spelling perl accepts for the same switch, including the one the rule exists for.

**Why:** R0071 code review 001 F2: `perl -we 'alarm 5; exec @ARGV' lune run x` and `perl -le 'while (1) {}'` passed the hook that refuses `perl -e` with `alarm` or a loop; the spec's refused list had only a bare `-e`.

**How to apply:** read the program's switches the way it does (bundles, attached values, switches that take the next word) before comparing, and put the bundled and attached spellings in the refused cases.
