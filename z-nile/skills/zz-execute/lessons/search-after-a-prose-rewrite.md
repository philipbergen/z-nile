---
title: After a script rewrites prose, search for what it gets wrong instead of trusting the read
when: both
tags: [rename, prose, review]
check: After the hand-rewording pass, does a search for the design's own named example of a half-rewritten sentence, and for the script's new path forms inside history sentences ("removed", "moved", "renamed"), come back empty?
---
A script that rewrites names in prose gets some sentences half right (a list where it renamed some words and rightly skipped others), and turns history into falsehood (a sentence about what a commit removed now names the new path, which that commit never touched). A line-by-line read of a large diff misses some of each.

**Why:** R0049 code review 001 F2: c0115's rename left c0083.md:113 as "zz-execute, review, tracker or z-design skills", the very example its step 5b names, while :376 was fixed; and a lesson said a commit "removed `z-nile/skills/zz-test/SKILL.md`", which it never did. Both survived the line-by-line reads of steps 5 and 5b.

**How to apply:** after the read, grep for the design's example pattern (`git grep -nE 'execute(-raft)?, review, tracker'`) and for every changed history sentence (`git grep -nE '(removed|moved|renamed)[^.]*(z-nile|pickman)/skills/'` over the changed lessons); reword each hit, or leave it only when it quotes the old form on purpose.
