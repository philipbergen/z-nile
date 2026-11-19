# Idea review 001

## Findings

- F1: The first Solution sentence, "makes it count with no second command", is false in two of the cases the idea itself describes. Ready only sees an approval on origin/main, and the non-goals say the command neither changes that nor merges the prep pull request. So an approval committed to an unmerged prep branch does not count until that pull request merges, which is a separate action. And when the publish or push fails, the approval only counts once the retry command runs. The sentence needs to claim only what the command does in each case: on origin/main it counts at once, on a prep branch it counts when the prep pull request merges, and on failure it counts after the named retry. Otherwise a reader can't tell what the promise is.

## Verdict

revise
