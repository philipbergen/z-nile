# Idea review 001

## Findings

- F1: The Problem's claim that the lessons "do not warn" is false as written. `z-design/status-labels-need-a-tracker-fact` already covers this failure. Its c0259 design review 004 F1 entry says "the pinned map also pinned each state, so no README could pass once any named issue changed state". Its How to apply says to "pin only what the executor may not change, read the state words from the delivered file and judge them against the tracker". Its check question asks "if the tracker moves one named issue a step and the README follows it, does the check pass". The real gap is narrower. That lesson treats "the check" as the one label-truth check (AC7), while c0264's AC6 was a second check: a vocabulary check that quoted `*captured* (c0248)` as a literal (see the 4ec9d90a fix). So the Problem should say that the existing lesson's question doesn't reach every check that quotes a label. The smallest Solution is then to extend that lesson's check question to every check in check.sh that names an id, not to write a separate new lesson that repeats its rule.

## Verdict

revise
