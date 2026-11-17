---
title: A lesson file written after the trace rides a re-finish of the top layer
when: build
tags: [trace, harvest, finish, lessons]
check: Does any commit after the top layer's finish touch a file outside the raft's and its tickets' tracker folders (a skill's lessons file among them), and if so, was the layer re-finished and `trace.md`'s `Commit:` repointed before `./zn trace <R> --check` is claimed?
---
`./zn trace --check` accepts, after the top layer's finish commit, only commits touching the raft's and its tickets' tracker files, and after `trace.md` only the raft document, `spend.md`, spend rows and the final review and refute files. A skill's `lessons/` file is neither, so a lesson written from the final review (Phase 5 step 4, which comes after the trace) makes the table stale ("commit … added to <layer> after trace.md").

**Why:** R0126: the final reviewer's candidate lesson was harvested as a note on `zz-review/trace-cells-cite-their-own-proof` after `trace.md` and `final-review-001.md` were committed, and `./zn trace R0126 --check` went stale. R0110 had the same need and folded its lesson files into the top layer's re-finished commit.

**How to apply:** write the lesson and the `harvest.md` line, commit them, run `./zn finish <top issue>` again (it squashes the layer, the review files and the trace with it, into one finish commit), then set `trace.md`'s `Commit:` to the new finish sha, commit only that, rerun `./zn trace <R> --check`, and push with `--force-with-lease`. A review file or refute committed after that needs no re-finish.
