# Idea review 001

## Findings

- F1: The solution isn't the smallest one that fixes the problem. Waiting until a pull request's checks pass and GitHub says it can be merged is mechanical, and `.models.toml`'s `[dispatch] auto_merge = ["prep", "raft"]` shows the dispatcher already merges green, mergeable prep and rafting gates itself without any model. A time-limited poll inside the dispatcher, ahead of that merge it already does, would solve the problem with no model. Instead the idea adds a "wait role" that doesn't exist (`.models.toml` has no `[roles.wait]` or any other wait role) and runs a model step just to poll. The phrase "the cheapest model its CLI names for a wait role" also can't be checked true or false until that role is defined.

## Verdict

revise
