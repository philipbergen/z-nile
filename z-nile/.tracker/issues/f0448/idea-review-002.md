# Idea review 002

## Findings

- F1: The third Problem sentence is false as the repo stands, and the fourth Solution sentence repeats an existing rule in a weaker form. Step 3 of z-design (`z-nile/skills/z-design/SKILL.md:25`) requires every item of `z-nile/skills/z-design/checklists/defect.md` to be answered in the Design. That checklist already has a **Siblings** item: "every other caller or place that makes the same mistake, each fixed in this issue or captured as its own". So a defect's design can't be accepted without saying what else the same root cause broke. The fourth Solution sentence asks only that the design *state* those other places, while the checklist requires each one to be fixed or captured, so as worded it loosens the current rule. The same checklist also already asks for **Reproduction** and **Root cause** at design. The idea never says whether the first two Solution sentences move those items to the idea stage or keep both copies. Either drop the third Problem and fourth Solution, or have them name the checklist and say what it lacks (for example, that nothing but the reviewer enforces it). The first two Solution sentences should also say what happens to the checklist's Reproduction and Root cause items.

## Verdict

revise
