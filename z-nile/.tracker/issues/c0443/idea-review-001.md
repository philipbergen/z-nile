# Idea review 001

## Findings

- F1: The non-goal blocks a change the solution needs. README.html says twice that the reference text is in README.md: its file list (`z-nile/README.md`: "The reference text: the current map of every part", line 468) and its footer ("The reference text stays in `z-nile/README.md`", line 474). Once the text moves, both lines are false. The non-goal says the idea "does not rewrite … the HTML page", so those two lines can't be pointed at the new place. The fence needs to allow changing README.html's references to README.md while still ruling out rewriting or restyling its content. Otherwise the solution leaves the HTML page sending readers to the short README for the reference text.

## Verdict

revise
