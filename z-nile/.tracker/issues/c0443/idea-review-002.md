# Idea review 002

## Findings

- F1: The Solution leaves out the specs of tickets that haven't landed. 25 of them have acceptance specs that read `z-nile/README.md`. Two are active in rafts: c0121 (R0084) and c0257 (R0128). The other 23 are in the backlog: c0175, c0178, c0247–c0254, c0258, c0260, c0262, c0263, c0267, c0280, c0282–c0284, c0316, c0394, f0339 and f0417. Most of these specs check phrases or Roadmap rows that their own ticket will add later. So "every phrase a spec pins today is still pinned there" doesn't cover them. Once `README.md` is a few sentences, those specs would fail, or their tickets would write into the short file, unless the idea says they move to the new file. The idea also doesn't say who edits another ticket's `check.sh` specs, including the two already in rafts.

## Verdict

revise
