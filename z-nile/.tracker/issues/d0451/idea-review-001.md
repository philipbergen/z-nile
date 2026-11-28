# Idea review 001

## Findings

- F1: Problem bullet 2 is false where it says "plus live-held units". A live-held unit with no `questions.md` is counted as in flight, the second count (`tributaries.luau` 155-174: `inFlight = active or holders > 0`; `board.luau` 1329-1345). The third count holds only open units where the unit or a member has a `questions.md`, which is what the cited audit line 31 says ("counts only units with `questions.md`").
- F2: Solution bullets 1 and 4 cannot be found true or false as written, because the approval facts are not a property of the tree. They come from the last `./zn approve --queue`, which has its own time and scope (`themewrite.luau` 34-47). The app shows "not known yet" when no queue was read, and warns that units outside a scoped queue have unknown approval state (`live.js` 746-773). The idea does not say what the board's count is in either case, so "for the same tree" fixes neither number.
- F3: Non-goal 2 is not a fence, because it leaves open a choice that decides whether Solution bullet 4 can hold. If the owner folds both into one "waiting for you" count, the board has no approval count to equal the app's, which keeps approval and owner as separate counts (`themefacts.luau` counts). Bullets 1 and 2 then hold only vacuously, so a relabel alone would satisfy bullets 1-3. The idea therefore does not settle whether the board must compute the approval count at all. It also leaves unsaid which of the four counts a `questions.md`-only unit lands in once bullet 2 removes it from the third.
- F4: The audit citation cannot be followed, and one line reference does not support its sentence. "audit-B.md of origin/main 3e7b197e3" gives no path; the file is `z-nile/.tracker/issues/f0450/evidence/audit-B.md`, untracked in another ticket's folder, not on origin/main. Line 83 is about f0423's stale design text (it says the board calls `waiting.unit`), not about the page and the skill; line 31 is the one that supports Problem bullet 3.

## Verdict

revise
