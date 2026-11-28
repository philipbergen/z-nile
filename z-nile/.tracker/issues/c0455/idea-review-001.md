# Idea review 001

## Findings

- F1: Problem 1's "about 303 with a single harvest source" is false as worded. `./zn lessons` shows 303 lessons at "1 source", but that count adds one for a `from:` key. 72 of the 303 have `from:` and no harvest citation at all, so 231 lessons have a single harvest source, and this is the number that sizes the prune.
- F2: Solution 1, 2 and 5 leave unfinished items undecided. 124 of the 231 single-harvest-source lessons have their only citation in the harvest of an item that is neither finished nor retired (backlog or active). Sentence 1 protects only finished and retired items, and sentence 2 does not say what makes a harvest "new", so a reader cannot tell whether those items pass or fail the check after the prune.
- F3: Solution 3's "did not recur across at least two items" cannot be found true or false. A first occurrence recorded as one-off leaves no lesson id, and the sentence names no test for when a later finding counts as the same mistake.
- F4: Solution 3 and Solution 5 disagree. Sentence 3 lets one finding that shipped as a defect earn a lesson, while sentence 5 retires every single-source lesson, including any that came from a shipped defect.
- F5: Solution 4 names "the graduation threshold" without a value. The list holds 243 lessons at 3 or more sources and 144 at 5 or more, and the sentence does not say whether a `from:` key counts as a citation.
- F6: Solution 4 is not needed by either Problem sentence, so the solution is not the smallest. Neither sentence says candidates are hard to find, and `./zn lessons` already prints each lesson's source count and sorts by it.
- F7: Solution 6's "written before harvests began" has no test a reader can apply. If it means the 92 lessons with a `from:` key, zz-rules defines that key as a source with no item folder, not a date. Four of those 92 also have exactly one harvest citation, so sentences 5 and 6 give them opposite outcomes.
- F8: Non-goal 4 is not a fence. It allows removal after an individual audit but does not say whether auditing the 92 lessons is inside this idea or left to a later one.

## Verdict

revise
