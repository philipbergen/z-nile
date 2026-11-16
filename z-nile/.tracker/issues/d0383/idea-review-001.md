# Idea review 001

## Findings

- F1: Problem 1 says the net "fails at once" and Solution 1 says it "fails to start", but neither gives a time window. If a net is still alive when the kick returns and dies a few seconds later, a reader can't tell whether that case is covered. So you can't judge whether Solution 1 holds, or whether the kick should exit non-zero then. State the limit, for example "exits within N seconds of the kick" or "before the kick returns", so the sentence can be checked true or false.

## Verdict

revise
