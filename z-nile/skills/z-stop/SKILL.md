---
name: z-stop
description: Undo z-ready, or abort a started raft. Gives the claim back, moves the raft and its issues out of `active/` on origin/main (stamped prepared), removes the prompt, and names the raft's branch and pull request, which it leaves as they are. Use for "stop R0010", "unready", "abort the raft", "/z-stop".
---

# Stop a raft

1. **Resolve the target.** It is normally a raft id (`R0010`). For an issue, look up its raft first (`./zn status <id>`, then the document's `raft:`). Only an active issue whose raft is retired, missing or empty (audit's `dead-raft` or `raftless-active` error) is stopped by its own id: `./zn stop <issue>` gives that one issue back to the backlog, stamped `prepared-…`, with its `check.sh` paths rewritten back; an issue whose raft is live is refused (stop the raft).
2. **Sync, then stop, in the main checkout.** Run `./zn sync`, then `./zn stop <R-id>`. It refuses anywhere but a clean `main` checkout with an origin. It is the only way to give back a readied raft: `status` refuses items in `active/`. It gives back exactly what the claim took: the raft and the issues carrying its own `active-…` stamp. An issue filed naming the raft after the claim keeps its status and is named in a warning; report it, and the human decides whether it belongs to the raft. A raft that carries no `active-…` claim stamp (an `active/` folder or status made by hand) is refused ("give it back by hand"): report it, and the human fixes the documents by pull request.
   - A readied raft (in `active/` on `origin/main`): one tracker-only commit moves it and its issues back to the backlog, stamped `prepared-…`, with their `check.sh` paths rewritten back. A member already in `done/` refuses, naming it.
   - A raft claimed by the legacy `start` (in the backlog, status `active`): a status-only publish gives the claim back, with no move.
   - Any other raft is refused with its status.
3. **Report** the printed lines. `stop` deletes `prompt.md`, pulls the main checkout and prints `stopped <R-id> (<ids>)`. If the raft's branch exists it also prints `<branch> and its pull request <url> are left as they are: close or keep them yourself`.
   - The branch and the pull request are left to the human, who decides whether to close the PR (`gh pr close`) and remove the worktree (`git worktree remove`). Never close, delete or remove them yourself.
   - Emergent issues that exist only on the raft's branch are not on `origin/main`, so `stop` does not see them.
4. **Re-readying.** `z-ready` can ready the raft again later. After a started raft, its old branch and PR still exist, and the human picks one of two ways. To start fresh, close the PR and delete the branch (`gh pr close <pr> --delete-branch`, then `git -C <root> branch -D <branch>` and remove its worktree), and `start` makes new ones. To keep them, run `start` on that branch in its worktree: it adds an empty commit, pushes, and reuses the open PR.
5. **Whose claim.** Stop only a raft whose claim is yours; ask the user before stopping one you did not ready.

## Lessons
Search with `./zn lessons <terms>` when you are about to do something a lesson might cover.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder: `z-nile/skills/` for z-nile's skills, `<project>/skills/` for a project's, never through a `.claude/skills/` link, which git can't add through; format: zz-rules skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (z-design step 5.3, zz-execute Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (z-ticket skill). The prep that takes the issue writes the file.
