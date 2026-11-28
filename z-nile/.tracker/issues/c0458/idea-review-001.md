# Idea review 001

## Findings

- F1: The Problem's "3.7% shipped rework rate" is only the by-lines-added figure. `./zn metrics` prints 11.1% by issues and 8.5% by agent time beside it, and the sentence gives no figure for review spend or turnaround, so "high compared with" cannot be found true or false.
- F2: "Each ticket gets exactly one adversarial review after it is built" is undecidable for a bundle of several tickets. Today such a bundle gets one review per layer plus one on the whole stack, and takes its highest member's risk. The sentence does not say whether three tickets get three reviews or one, or whose risk sets the model and cap. The trace check the Non-goals keep is filled by the whole-stack review.
- F3: "Optional for normal tickets" cannot be found false: it names no one who decides and no condition, so a normal ticket with or without a design review satisfies it equally.
- F4: The Solution is not the smallest for the stated Problem, which is about normal-risk tickets only and names no cost of the idea challenge. It also cuts the idea challenge from 3 rounds to 1, easy rounds from 2 to 1 and risky rounds from 9 to 3, and none of those clauses answers anything the Problem states.

## Verdict

revise
