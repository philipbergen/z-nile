# Idea review 001

## Findings

- F1: The Problem's first claim is false as written. `z-nile/skills/z-raft/lessons/order-names-members-once.md` already says the Order names "members only, each once" and "no other item id". It also says the engine reads every `[fdc]NNNN` in the section and refuses a repeat. Its R0100 note quotes the refusal ("c0277 is listed twice") and says to run `./zn stack <R-id>` after any edit to the Order section. `./zn lessons Order twice` finds it. A layer branch such as `R0090/1/c0261` carries a member id, so that lesson already forbids it, just not by name. Two things are really missing: the layer-branch form as an example, and the timing "on the rafting branch, before the rafting pull request". So the smallest solution is to extend that existing lesson, not to "hold a lesson" the skill already holds. As worded, a reader could also say the Solution is already done today.

## Verdict

revise
