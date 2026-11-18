# Idea review 001

## Findings

- F1: The Solution's "starts with the merge subject" puts no limit on what may follow, so the case would get weaker than it is now. A subject such as `R: bind a, b, c` (an extra issue) or `R: bind a, bx` also starts with `R: bind a, b` and would pass. Whether "may carry the session note after it" is the only thing allowed after the prefix, or just one thing that is allowed, can't be decided from the sentence. The smallest fix that keeps the exact check is to accept the subject with nothing after it, or followed by one space and the session note. `done` prints that note as `session: <note>`, so the case can compare against it. `sessions.combine` always writes a non-empty note (each CLI with no reading gets "<cli> unmeasured"), and `recordAndCommit` adds it to the first share's row, which is issue a's. So in practice the note is always there.

## Verdict

revise
