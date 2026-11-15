# Idea review 001

## Findings

- F1: The first Problem sentence is false for `./zn status <id> prepared`. The preparing→prepared move calls `designOpen` (`z-nile/engine/main.luau:1598`), and that runs `openlist.problem` (`main.luau:1496`), the same full rule `./zn ready` applies through `readycheck.luau:74`. That rule covers refuted findings, highs not answered fixed and failed Judged criteria. Only `./zn approve` checks just that bullets are ruled, via `openlist.pending` (`main.luau:5846`). So the Problem misnames which commands disagree. The Solution's "same verdict" line then covers a command whose verdict already agrees with `ready`, so the smallest fix is `approve` alone. The tagged-answer sentence holds: `openlist.answerKind` (`openlist.lua:51`) matches only `- F1:`, so `- F1 [high]: …` reads as unanswered.

## Verdict

revise
