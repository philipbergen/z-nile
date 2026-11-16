# Idea review 001

## Findings

- F1: The Solution has the raft land without waiting for the added issue's approval, and has the added issue implemented after approval. It never says where that issue goes once its raft has landed. A raft is one branch and one PR (zz-execute), so after the merge an unapproved member has no open raft to be implemented in. The only existing home for an unimplemented issue outside a raft is the backlog. If it goes back there, the problem returns: findings still become backlog tickets. As written, a reader can't tell whether "added as a new member issue to the raft that found it" still holds after the raft lands. The same gap applies to a finding made while designing an issue, before z-raft has grouped it into any raft.

## Verdict

revise
