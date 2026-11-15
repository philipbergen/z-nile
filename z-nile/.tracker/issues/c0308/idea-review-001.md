# Idea review 001

## Findings

- F1: The lesson this Solution asks for already exists. `z-nile/skills/z-design/lessons/prove-specs-pass-on-a-prototype.md` has this check: "is the prototype's base still `origin/main` for every file the specs load (the Touched modules and anything a spec reads), with the specs, mutants and gate re-run after any change there?". Its R0044 design review 5 (F1) note also says: "Before each review round and before the prep commit, run `git diff <prototype base> origin/main -- <Touched modules and files the specs load>`; if it is not empty, merge, rebase the prototype and re-run everything." `in-flight-bases-pin-their-source.md` adds a recut "as the last step before landing". So c0261's redesign went stale even though the lesson was there. A second lesson worded almost the same way is not the smallest fix, and nothing in the Solution explains why it would work when the first one didn't. The Solution should name the existing lesson and the gap that let c0261 through. One candidate: the check fires "before each review round and before the prep commit", not before the approval request of a redesign that comes back after a fold. Then it should change that lesson rather than add a new one.

## Verdict

revise
