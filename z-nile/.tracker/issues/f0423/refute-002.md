# refute-002

Answers to code review 002 of f0423 step 1 (branch f0423-walk).

- F6: fixed: the lower raft now has the higher raft id (R0003 under R0002; the inconsistent-Order raft is R0001), so the stack order differs from id order by raft name too; the mutant `waiting.order(placed, {})` in `approvewalk.luau` turns the "--queue writes the run for a raft and the stack under it, bottom first" case red (1 failed) and was reverted; consequences: none.
- N1: fixed: the apply prompt is one line (title, why it waits, guess count, where it records), then at most 5 guesses as `G<n> chose: <first 80 characters>…`, then "and N more: see <brief path>" when there are more, and no list for 0 guesses; spec with 0 (a redesigned ticket whose approval is stale), 1 and 12 guesses and a 300-character Chose; consequences: a prompt no longer shows every guess in full (the brief does).
- N2: fixed: a local contract that cannot be built is refused naming the error ("<id>: this checkout's copy of the contract cannot be built: <why>"), and a place that is a prep worktree gets only "walk from <worktree>"; spec for both; consequences: none.
- N3: fixed: the agent-marker refusal gains "If this is your own terminal, open a new one that no agent CLI started." in the one place it is built (`approvewalk.markerRefusal`, used by `main.luau` too); the launch spec's stub CLI exports `CLAUDECODE=1` before it tries to record and the parent still records after it exits; consequences: none.
- N4: fixed: the Overrides entry for `f0399/land.spec.luau` says the spec passed everywhere before this change and that this change's engine guard would make it fail inside an agent session, so the helper clears the markers and tests the person's path; consequences: none.
