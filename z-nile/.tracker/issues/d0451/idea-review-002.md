# Idea review 002

## Findings

- F1: Solution sentence 3 would be false of the board as written: `./zn approve --queue` does not change the board page. It writes `approvals.json` and remakes only `themes.json` (`z-nile/engine/approvewalk.luau` lines 667-708; `refreshThemes` in `z-nile/engine/main.luau` lines 6217-6227 calls `themewrite.refresh`, main checkout only). Nothing in that path rewrites `.cache/board.html`. So a reader who runs the command the board names and reloads still sees "not known", while the app updates. For the same reason, sentence 2's condition (same approval facts file) stops holding after every queue run, and the Solution does not have the board state when its approval facts were read, though the Problem notes they carry their own time and the app shows it. The Solution has to say what makes the board's approval count current (the queue also rebuilds the board, or the board names the step that does) and whether the board shows the facts' time.

## Verdict

revise
