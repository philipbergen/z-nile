# Refute 003: c0135 (design mode)

Design review 003 approves; its three lows are fixed in this final round.
- F1: fixed: the hint is per kind. An issue keeps "edit slug: in all but one; branch and worktree names need not follow"; a raft gets "edit slug: in all but one, never in a raft that has its <id>-<slug> branch: the branch name is derived from it". The Design says a raft's branch name is derived from its slug and is a key. slugs.spec pins the raft line (a backlog R0098 sharing R0004's slug). consequences: the pinned issue line is unchanged.
- F2: fixed: a two-op plan with different bases, both taken, expects `a-2` and `b-2`; the reviewer's mutant (a counter shared across the plan with the skip loop kept) fails it on the prototype, and the Rules row says so.
- F3: fixed: the case expects audit's `audit: ` summary line after the fix, so a crash before the report can't pass for clean.
