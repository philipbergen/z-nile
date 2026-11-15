# Idea review 001

## Findings

- F1: The first Solution bullet only asks for the lines to be "still present in the issue", but the first Problem bullet is about them being lost from the Problem. Under that wording, an idea run could move every Decided line, Scope decision line and the carried-from note word for word into Solution or Design and still pass. The Problem would still be replaced without them. That is close to what c0306's run did: its decisions survived only as Solution bullets. Yet z-design's "Scope is what was captured" puts Scope decision and Decided lines in the Problem, and the lesson `idea-runs-keep-decided-lines` checks that "the new Problem still hold[s]" them. The bullet should say where the lines must end up.

## Verdict

revise
