# Idea review 002

## Findings

- F1: Solution bullets 3 and 5 can't both be true while ticket code still reaches the host through pull requests. Bullet 3 says `.git/info/exclude` is the only host file zn writes outside `.tracker`, `.worktree/` and `.cache/`. Bullet 5 says zn makes no commit on any host branch and pushes nothing to the host remote. A pull request needs a branch, commits and a push. Making the worktrees bullet 6 assumes also writes host files outside those three paths: `.git/worktrees/<name>`, `.git/refs/heads/<branch>`, new objects in `.git/objects`, and `.git/config` if a fork remote or upstream is set. Running `./zn work` on one ticket against omarchy and watching the host `.git` would show those writes, and the ticket branch reaching some remote. Either the bullets mean work that the zn-run worker does doesn't count as zn's, which a reader can't check, or they are false. The idea has to say who creates the branch, the worktree and the commits, and which remote gets the push (the host's origin or the owner's fork). Then these two bullets can be checked.

## Verdict

revise
