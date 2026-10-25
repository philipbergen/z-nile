# Refute 001: R0049 (code mode)

Reviewer spend (`./zn spend` refuses the code-review phase and `./zn commit` refuses this branch, impl-c0115): 9 minutes, 228660 tokens.

- F1: fixed (PR #120's description, edited 2026-10-25; no commit): the description now states R0049, the rebase onto landed c0120, the commits by kind, the `-s ours` merges, the G4 list step 5b requires (the seven documents, the three sequestered files under the user's exception, the sentences reworded by hand), the results at the reviewed head, and the landing note; consequences: none (the PR body is no input to any check).
- F2: fixed 9f1eb875: c0083.md:113 reads "zz-execute, zz-review, zz-rules or z-design skills", like its AC8 at :376; the lesson `z-design/exact-checks-compare-against-the-merge-base` says in words which file the commit removed (the old file of the skill now called zz-test, in the old links folder); consequences: AC4's absence scan and AC14's backlog scan rerun clean (`./zn check c0115` 15/15 after the fix); `git grep -nE 'execute(-raft)?, review, tracker'` now finds only the two places that quote the example on purpose (c0115.md:487, design-review-007.md:62).
