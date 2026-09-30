# pickman

A first-person Pac-Man clone for Roblox, built with Rojo, strict Luau, and Lune for headless tests. New machine: see `SETUP.md`.

**Non-negotiable:** no code without a tracker issue, and work is done only when its `check.sh` passes. **Every change is made in a git worktree under `.worktree/` and lands by pull request**; the main checkout is never edited (tracker skill, Worktrees and Landing a change). Before doing anything, read the skill that applies. The skills hold all the rules.

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
