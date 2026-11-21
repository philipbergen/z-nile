# Idea review 002

## Findings

- F1: The second Solution bullet contradicts the fourth. The board can't name "the worker that carries it" while being "built only from files committed to the tracker repository", because today no committed file records the worker. The claim `ready` publishes is a random `active-…` stamp in the `status:` line. Who carries what is kept in the ignored `.cache/work/` carriers file, which the fourth bullet says never appears on the page. z-work's SKILL.md also says a release commit doesn't name the session, and that "the holder is the author of the ready commit" is left for c0254. That is commit metadata, not a committed file. Read literally, no build can meet both bullets. The idea has to say where the worker's name comes from: something that starts getting committed, the ready commit's author (which then needs to be allowed as a source), or nothing, with the worker dropped from the board.

## Verdict

revise
