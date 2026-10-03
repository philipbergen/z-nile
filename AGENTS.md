# pickman

A first-person Pac-Man clone for Roblox, built with Rojo, strict Luau, and Lune for headless tests. New machine: see `SETUP.md`.

**Non-negotiable:** no code without a tracker issue, and work is done only when its `check.sh` passes. **Every change is made in a git worktree under `.worktree/` and lands by pull request**; the main checkout is never edited (tracker skill, Worktrees and Landing a change). Start an agent with `scripts/tracker.sh launch <target>`. Before doing anything, read the skill that applies. The skills hold all the rules.

**No check may ever change the real repository.** Specs, `check.sh` files and the scripts they run change only throwaway fixtures under `.cache/`. The runner enforces it. On macOS it runs specs in a jail that denies every write to the repository outside `.cache`; a run that can't be jailed (inside another sandbox) refuses to start unless that sandbox already protects the repository. Everywhere it fences git into `.cache`, refuses ref updates and pushes into the real repository, runs one suite per checkout at a time, and fails any run during which the remotes, config, branch or history changed. What it can't see (unjailed runs on Linux, `check.sh` files' own commands, work handed to processes outside the jail), review must catch (testing skill, "Specs never touch the real repository"). If its tripwire fires, stop and report: never repair the shared git configuration yourself.

| Skill | Read when |
|---|---|
| `.claude/skills/tracker/SKILL.md` | creating, moving, committing or finishing tracked work |
| `.claude/skills/architecture/SKILL.md` | designing or writing anything in `src/` |
| `.claude/skills/testing/SKILL.md` | writing specs or `check.sh`, running the gate |
| `.claude/skills/make-issue/SKILL.md` | capturing a new feature, defect or chore |
| `.claude/skills/ticket-prep/SKILL.md` | grouping issues into a raft and designing it (includes the design review) |
| `.claude/skills/make-prompt/SKILL.md` | producing the clipboard prompt for a raft or issue |
| `.claude/skills/execute-raft/SKILL.md` | implementing a raft: one branch, one PR |
| `.claude/skills/review/SKILL.md` | acting as, or launching, the adversarial reviewer |
| `.claude/skills/metrics/SKILL.md` | cost and rework reporting |
