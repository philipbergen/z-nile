# Idea review 001

## Findings

- F1: The idea never says where the tickets live, and as written they have nowhere to go. The worker, the board and the approval walk all read tickets and move them, and today zn does that by committing them into the repository (z-ready moves a raft to `active/` on origin/main). The last Solution sentence forbids anything of zn in the host's commits or tracked files. The first non-goal rules out a separate ticket repository. What is left is ignored local files, and the idea doesn't say that. So nobody can tell whether "every one of those commands works" is true. Example: running the worker in an omarchy checkout means claiming a raft, and the idea doesn't say where that claim is written. The same gap hits "the repository's own settings" that name the gate's test command. If they are a file in omarchy, they break the last Solution sentence. If they are not, the idea doesn't say where they are.

## Verdict

revise
