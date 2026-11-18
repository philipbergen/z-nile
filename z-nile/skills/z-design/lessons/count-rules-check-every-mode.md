---
title: A count-by-folder rule is checked against every mode that shares the folder
when: design
tags: [dispatcher, siblings, review]
check: When a defect is a rule that counts files in a folder to refuse a repeat, which other callers file into the same folder under the same prefix (a review per layer, per stream, per round), and does the rule's key name the subject of the repeat or only the folder?
---
A "one review" rule that counts `review-NNN.md` in a raft folder measures the folder, not the subject. Where several subjects file into one folder (a code review per layer of a raft), the rule refuses the second subject's first review.

**Why:** d0415 design review 001 F5: the dispatcher's code mode counts every `review-NNN.md` in the raft's folder, so layer 2 of a raft is refused although no review of layer 2 exists; done rafts hold up to ten such files. The defect under repair was the same kind of mistake in raft mode.

**How to apply:** in the defect checklist's Siblings item, list each mode or caller that files under the same prefix in the same folder and say what its subject key is; if the rule's key is the folder and the subject is finer, name it and put it to the user when a Non-goal fences it.
