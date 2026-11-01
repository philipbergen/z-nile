---
title: A sequestered check proves nothing through files the branch can rewrite
when: design
tags: [check-sh, sequestration, experiments]
check: For each file this check.sh reads or runs (an item's `experiments/` patches or harnesses, another item's document), is it sequestered, pinned by blob, read from the merge base, or covered by an unchanged-from-base check?
---
**Why:** c0174 design review 005 F1 (medium): AC3 compared c0083.md with its merge-base text plus `experiments/c0083-doc.patch`, and AC2 ran `experiments/folder-case.luau`. Neither file is sequestered, so an execution could edit the document, regenerate the patch to match, or gut the harness, and pass 5 of 5 while the sequestration diff of the reviewer saw nothing. It is the same mechanism as the tolerance for an unchosen route (z-design/rederive-tolerances-from-the-decided-route).

**How to apply:** list every input of the check, and put each input the branch should not change under an unchanged-from-merge-base check (a glob pathspec that survives the move to `active/` and `done/`), or pin it by blob; then run the clone state "edit the judged file and regenerate its patch".
