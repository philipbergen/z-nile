# Idea review 003

## Findings

- F1: The third Problem sentence and the last Solution sentence talk about "build briefs", but briefs aren't kept anywhere, so a reader can't check either claim. The warning that can be checked lives in two zz-arch lessons. `./zn lessons main.luau local` returns `zz-arch/main-luau-local-limit` (marked "both") and `zz-arch/engine-main-local-limit` (marked "build"), and both still say main.luau "is at Luau's 200-local limit". The same warning also appears in comments at `z-nile/engine/main.luau:6205`, `main.luau:7894` and `z-nile/engine/liveemit.luau:11`. The Solution never says what happens to those lessons and comments. If they stay, they keep telling every build not to add a top-level local after the split, and "briefs no longer carry the warning" never comes true. The two sentences should name the lessons and comments, and say whether they are retired or rewritten.

## Verdict

revise
