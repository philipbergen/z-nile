# Idea review 002

## Findings

- F1: The first non-goal is not a real fence, because it contradicts the first Solution sentence. That sentence says the skills and the README use no word other than the six for a stage. The non-goal lets the design keep the folder names `new`, `active` and `done`. The skills name those folders today: z-ready says it "moves it and its issues to `active/`" and writes `<root>/rafts/active/<R-id>/prompt.md`, and zz-rules says "`…/active/<ID>` is in progress, and `…/done/<ID>` is finished". If the folders keep their names, the skills still have to print `active` and `done` to say where a stage's items live, and the Solution forbids that. So the ticket has to decide one of three things now: rename the folders; let the Solution say that folder paths and stored values may still appear in paths; or drop the skills and the README from the places the Solution covers. Leaving the choice to the design doesn't work, because one of its two options breaks a Solution sentence. A smaller point on the same lines: `./zn close` writes `status: closed-…` (zz-rules skill, close), not `status: closed`, so the Solution's `status: closed` doesn't match what the tracker writes.

## Verdict

revise
