# Idea review 002

## Findings

- F1: The three trigger events don't map to clear z-nile steps, so a reader can't check the "started", "pull request opened" and "exactly three" sentences. A ticket has several pull requests: its design (prep) PR, the rafting PR, and the implementation PR it shares with the rest of its raft. "The ticket's pull request opens" could mean any of these. "Work on the ticket starts" could also mean the start of design, or z-ready claiming the raft. And when a raft is stopped and readied again, it is unclear whether a second "started" update gets posted, which would break "exactly three". Each sentence should name the step that triggers its update (for example, z-ready claiming the ticket's raft, the raft's implementation PR opening, and the ticket reaching done). It should also say what happens when a raft is stopped and readied again.

## Verdict

revise
