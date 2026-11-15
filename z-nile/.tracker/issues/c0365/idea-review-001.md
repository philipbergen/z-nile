# Idea review 001

## Findings

- F1: The Solution's two halves cover different sets of issues. The flip is limited to "the layer's own issue", but the check afterwards requires "no *designed* marker left" for "each issue the layer touches". Suppose a layer edits or rewords a line that names another issue that isn't built yet, such as c0265's layer touching c0276's line "The board shows lost, parked and stale claims, lost first. *designed* (c0276)". The check would then call that correct *designed* marker an error. A reader can't tell whether a lesson that tells you to flip only your own issue's marker, and then fails you for leaving another issue's marker alone, says what it means. The check should name the same issue as the flip: the layer's own issue. (The other claims hold. No current lesson in `z-nile/skills/zz-execute/lessons/` mentions the Roadmap. R0100's c0265 README hunk does not apply cleanly on its re-pick base, so there really was a conflict for the lesson to apply to. R0099 review 003 records the duplicate rows `exists` and `designed`. The non-goal fences off the change to the selector, which c0364 is doing.)

## Verdict

revise
