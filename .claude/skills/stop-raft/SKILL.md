---
name: stop-raft
description: Undo ready-raft, or abort a started raft. Gives the claim back, moves the raft and its issues out of `active/` on origin/main (stamped prepared), removes the prompt, and names the raft's branch and pull request, which it leaves as they are. Use for "stop R0010", "unready", "abort the raft", "/stop-raft".
---

# Stop a raft

1. **Resolve the target.** It must be a raft id (`R0010`). For an issue, look up its raft first (`scripts/tracker.sh status <id>`, then the document's `raft:`).
2. **Sync, then stop, in the main checkout.** Run `scripts/tracker.sh sync`, then `scripts/tracker.sh stop <R-id>`. It refuses anywhere but a clean `main` checkout with an origin. It is the only way to give back a readied raft: `status` refuses items in `active/`.
   - A readied raft (in `active/` on `origin/main`): one tracker-only commit moves it and its issues back to the backlog, stamped `prepared-…`, with their `check.sh` paths rewritten back. A member already in `done/` refuses, naming it.
   - A raft claimed by the legacy `start` (in the backlog, status `active`): a status-only publish gives the claim back, with no move.
   - Any other raft is refused with its status.
3. **Report** the printed lines. `stop` deletes `prompt.md`, pulls the main checkout and prints `stopped <R-id> (<ids>)`. If the raft's branch exists it also prints `<branch> and its pull request <url> are left as they are: close or keep them yourself`.
   - The branch and the pull request are left to the human, who decides whether to close the PR (`gh pr close`) and remove the worktree (`git worktree remove`). Never close, delete or remove them yourself.
   - Emergent issues that exist only on the raft's branch are not on `origin/main`, so `stop` does not see them.
4. **Re-readying.** `ready-raft` can ready the raft again later. After a started raft, its old branch and PR still exist, and the human picks one of two ways. To start fresh, close the PR and delete the branch (`gh pr close <pr> --delete-branch`, then `git -C <root> branch -D <branch>` and remove its worktree), and `start` makes new ones. To keep them, run `start` on that branch in its worktree: it adds an empty commit, pushes, and reuses the open PR.
5. **Whose claim.** Stop only a raft whose claim is yours; ask the user before stopping one you did not ready.
