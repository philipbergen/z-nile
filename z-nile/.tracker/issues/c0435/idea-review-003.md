# Idea review 003

## Findings

- F1: The third Problem sentence says only the review round cap scales with risk, and that is false. An easy ticket already gets the light path. `./zn ready <issue>` makes its single raft with no rafting step, the separate code review is skipped, and the final review is its only code review (`z-nile/skills/z-ready/SKILL.md:8`, `z-nile/skills/zz-execute/SKILL.md:62`, `z-nile/skills/zz-review/SKILL.md:137`). Code review rounds also have their own per-level cap (`[rounds]` `code`, `z-nile/skills/zz-rules/SKILL.md:185`). The Solution never mentions the light path either. On that path the final review already covers the code, so the new review of "design and code together" plus "Every ticket keeps … the final review" puts a second code review back where today there is one. The idea needs to say how the combined review relates to the light path's final review, and whether it replaces or adds to it. Until it does, it isn't clear this is the smallest change.

## Verdict

revise
