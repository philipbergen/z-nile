# Idea review 003

## Findings

- F1: "The board shows it" can't be checked true or false, and neither problem needs it. There is one board for all sessions (`.cache/board.html` in the main checkout), and any session's publish or `land` refreshes it. The README says workers on other machines show up on it too. If two sessions run under different profiles, or one runs under a profile and another with none, the sentence doesn't say which profile the board shows. It also doesn't say whether a session with the variable unset changes the board, which the first non-goal requires it not to. The first problem is solved by the variable and the file. The second is solved by the four writes and the reports. The worker's start-up line already tells the person which profile is in force. Either drop the board from this idea, or say exactly what it shows for each session that is running.

## Verdict

revise
