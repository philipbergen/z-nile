---
title: A reasoned row's reason is a claim the reviewer can test
when: design
tags: [mutants, specs, review]
check: For each Rules and mutants row marked `reasoned`, is its stated reason (why the mutant cannot be observed, or why no case is needed) true of the frame, the events and the public API, checked by trying to observe it? Before calling a mutant observable only through a long play sequence, has the hand-set state the spec's neighbouring cases already use (flipping a status or a flag) been tried?
---
`reasoned` lets a mutant go unkilled on the author's word. A reason such as "no public observation tells X" is easy to write and often false: the frame or the events carry more than the author remembered.

**Why:** f0126 design review 001 F2: row G1 said no public observation showed which maze a member's ghosts walk, but ghost positions are in every frame, and a ghost standing in a hole shows it; a seed search found one in seed 28.

**How to apply:** before marking a row `reasoned`, try for a few minutes to observe the mutant through the frame, the events and a seed search; write down what was tried. If it can be observed, write the case; if not, say exactly why, so the reviewer can check the claim.

**Also:** f0147 design review 005 F2: the eaten ghost's carry was called observable only after a full eyes run; flipping the ghost back to blue by hand, as the neighbouring cases do, observed it in five lines.

**Note** (c0265 design review 023 F2): "a collision cannot be observed" is rarely true: a stand-in can answer the collision check as taken, so no case waits for a real collision. Check: can a stand-in answer, as taken, the check the row says cannot fire?
**Also:** c0246 design review 001 / R0088 code review 001 F1: row N15 said a file name with a newline cannot be made in a throwaway fixture; `fs.writeFile` makes one in a line, and the PATH stub the neighbouring case already used reached the other branch. Eight design rounds passed the reason unchallenged.

**Note** (c0348 design review 001 F2): "no fixture can make it fail" is rarely true of a git step. A hook in the fixture repository's own hooks folder (`pre-commit` for a local commit, `pre-receive` on the bare origin for a push) fails that one step alone, and the fence's hook stubs run it. Ask: before marking a failure path reasoned because it cannot be produced, has a hook in the fixture's own repository been tried?

**Note** (c0253 prep, 2026-11-16): a mutant that removes the guard against starting a real model CLI must stay `reasoned`, never run, because running it starts the user's real `claude`. Say so in the row, and pin the guard with a case that uses a fake CLI.

**Note** (d0331 design review 002 F1, 2026-11-19): a row was marked `reasoned` as an equivalent mutant because "restack rebuilds the base and moves layer 1 in the same command". A restack that stops part way (a conflict, a red check, a rejected push) after the first of those two writes leaves the state that tells them apart. Before calling a mutant equivalent, list the command's failure paths and the state each leaves behind.

**Note** (c0178 design review 005 F22, 2026-11-24): 14 of 17 rows were only 'reasoned', and three could not fail: a case named after the template plus a suffix (no file holds the template path as a prefix of a longer name, so plain replacement passes), a decoy that differs in name and place at once, and a clone that takes the macOS path where the listed `cp -R` mutant is never reached. Check: for each row, does the mutant reach the code the case runs on this host, and does the case differ from the mutant's world in exactly the one thing the rule is about?
