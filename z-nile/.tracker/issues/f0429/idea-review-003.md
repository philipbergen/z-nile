# Idea review 003

## Findings

- F1: The second Solution line ("every ticket and raft under one of three headings (being worked on, waiting, done)") contradicts the fourth Non-goal ("the board's layout … stay as they are, apart from what publishing needs"). It also goes beyond the smallest solution. Today's board (`z-nile/engine/boardview.luau:17`, `z-nile/engine/board.html:289`) sorts tickets into six columns: ticket, design, raft, ready, run and done. Its Flow page uses the bands "In flight", "Workable now" and "After n steps". Its tributary counts already use "waiting" for a narrower meaning, "waiting for approval". Publishing doesn't need a new three-way grouping, and none of the three Problem lines says the current grouping is wrong. So either that line is new layout work the fence rules out, or the fence isn't real. A reader can't tell which. They also can't tell whether a backlog ticket counts as "waiting" in the board's existing sense or in this new one.

## Verdict

revise
