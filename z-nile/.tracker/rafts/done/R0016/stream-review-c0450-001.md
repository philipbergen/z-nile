# Review 001: c0047 (stream mode)
Inputs: `git diff R0016-board-artifact-spec-guard...ws-c0047` (5 files), tracker/issues/active/c0047/c0047.md, check.sh, acceptance spec. Ran `scripts/tracker.sh check c0047` (6/6 pass) and `scripts/check.sh --affected` (passed).

Scope: diff touches only the three skill files, the issue template, and c0047.md (verification log append). No check.sh or acceptance change; no stray files. Text matches the Design: Override check bullet sits in step 3 between Regression guard and Test plan with all required anchors; review item 4 extended with all tokens and **high**; make-prompt readiness bullet has `depends_on`, `isn't a member`, `done/`, `stop`; template `Overrides:` line is visible, outside the comment.

### F1 [low] The ticket-prep bullet says "A chore changes S in its own raft" without noting the chore's own `Overrides:` line
Where: .claude/skills/ticket-prep/SKILL.md, Override check, first sub-bullet
Evidence: the chore-on-chore case is covered only in the next sub-bullet ("c names S on its own Overrides: line"); a reader of a chore issue could skip the Overrides line. The step still says to name S for every overridden spec, so this is covered by reading.
Critique: clarity only.
Consequences: none.
Recommendation: optional; no change required.

Verdict: approve
