# Answers to design-review-002 (c0264)
- F1: fixed: the text moved into the sequestered `check.sh` (a heredoc) and `intent.txt` is deleted; consequences: none.
- F2: fixed: the whole-diff check is dropped; "no README line is lost" is JC1 for the code reviewer; consequences: a Judged criterion with a rubric.
- F3: fixed: the last sentence now says the worker-designs lines are plans, which is true; the open question has options (a), (b), (c) with costs and goes to the user in the report and the PR description; this design builds (c); consequences: a follow-up chore once the user picks.
- F4: fixed: AC1 checks the order of the `##` headings and pins no sentence (a section between Intent and How it should work fails it, run); consequences: none.
- F5: fixed: the three spec headers describe the present design.
- F6: fixed: the four specs join AC5 and Affected specs (twelve, run, pass).
