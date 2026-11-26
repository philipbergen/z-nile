# Idea review 003

## Findings

- F1: The sentence "A ticket that reaches done therefore leaves exactly three updates on its issue" does not follow from the solution, and a reader can find it false. Nothing says what zn does when a post fails, for example when gh is signed out, the network is down, GitHub refuses the comment or the issue has been locked. Say `./zn ready` claims the raft while gh is signed out. Either the claim fails, which means a GitHub outage blocks readying a raft. Or the claim goes ahead without the "started" update and nothing posts it later, and the ticket reaches done with two updates. The idea has to pick one: a failed post either blocks the step, or zn posts it later (and the record on the ticket says which updates are still owed). Without that, the "exactly three" promise doesn't hold.

## Verdict

revise
