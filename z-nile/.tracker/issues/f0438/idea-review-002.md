# Idea review 002

## Findings

- F1: Problem bullet 3 says "the app" shows an idea's text, and that is false. No app exists yet. There is only f0425's `mockup/index.html`, which runs on simulated data, and f0437 is the backlog ticket that would build the real app. Solution bullet 3 then has this ticket show attachments in that app, and `depends_on` is empty. So the solution takes on part of a view that another ticket owns and that has not been built. That part should be a fence (the app's view of attachments belongs to f0437) or a dependency on f0437, not a line in this solution.
- F2: Problem bullet 2, "one copied in by hand is not kept as part of the ticket", is false as written. A hand-copied file that is committed in a ticket's folder moves with it. f0425's `mockup/index.html` was copied in by hand and is committed in its folder. Folders such as `done/c0053/replacements/` and `done/c0084/experiments/` reached `done/` along with their tickets. What the bullet seems to mean is that nothing (the board, the briefs, `./zn idea`) knows the file belongs to the idea. As worded, a reader checking it would find it false.

## Verdict

revise
