# Idea review 002

## Findings

- F1: The Solution covers two surfaces but leaves out the board the owner uses today. It gives the start control to "the local app" and only a copy control to "a published board". The board that exists now is neither of those. It is the local page `./zn board` writes to `.cache/board.html` and opens in the browser (README: "The board is the local page"). The public board is only f0429, not built yet. So a reader can't tell whether the local board gets the control that starts `zn talk` or only the copy control. If it gets only the copy control, the third Problem sentence ("a command that must be copied into a terminal by hand is not that link") stays true on the one board that exists. That board then only gets a link once the app (still the f0425 mockup on simulated data) is built. The Solution and Non-goals need to say which side the local board is on.

## Verdict

revise
