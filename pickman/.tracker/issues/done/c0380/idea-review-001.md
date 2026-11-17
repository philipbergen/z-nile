# Idea review 001

## Findings

- F1: The f0145 parts can't be checked as written. f0145 is only prepared: its specs are still in `pickman/.tracker/issues/f0145/acceptance/` and none are promoted under `pickman/tests/acceptance/`. So the Problem's claim that promoted f0145 specs pin these texts is false today. "Passes … on main as it is today" also can't hold for any f0145 case, because f0145's code isn't on main, and neither can "every f0145 case … still passes." The text also doesn't say which prototype it means: there are two, `proto-f0186` and `proto-f0186-on-f0145`. Name the baseline (main with f0145 landed, or `proto-f0186-on-f0145`) and the prototype ref, so a reader can find each sentence true or false.

## Verdict

revise
