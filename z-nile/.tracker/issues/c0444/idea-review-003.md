# Idea review 003

## Findings

- F1: Problem 4 and Solution 3 never say which values count as a "state", so "each state has one colour of its own, different from every other state's colour" can't be judged true or false. "Easy, normal, risky and the others" are risk levels, and on these pages they appear only in the f0425 mockup (`z-nile/.tracker/issues/f0425/mockup/index.html`) and as prose in `README.html`. The board's coloured values are something else: the stage badges `new`, `preparing`, `prepared`, `active` and `done` (`z-nile/engine/board.html:44-48`), the types `feature`, `defect` and `chore` (`board.html:29-31`), and the worker state `lost` (`board.html:106`). A reader can't tell whether the board's stage badges are covered at all. Nor can they tell whether a risk level and a stage, or a type and a stage, may share a colour. The idea needs to list every value it means by "state", grouped by kind if the rule is per kind.

## Verdict

revise
