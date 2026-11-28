# guesses
- G1 (design, 2026-11-28): risk of c0460 Chose: normal Why: keeps z-design sequestered acceptance specs behavioral and moves build-time mutant records outside hashed Test plan
- G2 (design, 2026-11-28): does the mutants.md exemption ignore .tracker paths Chose: yes, bookkeeping files under .tracker/ do not count as code Why: commit and finish write spend.d and results.txt into layers, so the docs-only exemption would be unreachable
- G3 (design, 2026-11-28): how to keep fixtures from arming the rule and misformatted lines Chose: engine.copy strips the line from fixture templates; a near-miss Mutants: line refuses at finish Why: otherwise 20 finish-driving specs go red and a typo leaves a ticket unarmed
