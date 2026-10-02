# Refute 007: R0200 (re-prep: publisher on git mktree)

- F1: fixed.
  - **Parsing:** every `ls-tree -z` record must parse as `^(%d+ %a+ %x+)\t(.+)$`, or the publish refuses (`cannot read the tree at <path>: …`).
  - **Diff guard:** before `commit-tree`, a checked `diff-tree -r --no-renames -z --name-only <base tree> <new tree>` must list only the change's paths, or the publish refuses.
  - **New case:** `publish :: files with spaces, tabs or other odd names beside a change are kept exactly`. It plants `read me.txt`, `tracker/odd<TAB>name.md`, `tracker/issues/naïve notes.md`, `tracker/issues/x  y` and a 100755 `tracker/issues/run me.sh`, at every level the publisher rebuilds. It then asserts that exactly one path changed and that every other `ls-tree -r -z` record is byte-identical.
  - **Mutants:** MK3 (names as non-space runs, your mutant) and MK4 (unparseable records skipped, with no diff guard) are killed. 39 cases pass, in a `$TMPDIR` clone with no origin.
  - **Consequences:** two new Rules rows; E9 is updated.
- F2: fixed. The refusal message names the whole path (`tracker/issues/c0402 is a file on origin/main, not a folder`). A new case, `publish :: a path whose folder is a file on origin is refused, naming the whole path`, kills MK5 (no check). There's a Rules row for it.
- F3: fixed. The base tree is resolved with `rev-parse --verify <sha>^{tree}`, and its exit status and hex output are checked like every other step.
- F4: fixed.
  - AC9 now greps all of `scripts/tracker/` for the index names, and requires `"mktree"` as a quoted argument in `publish.luau`.
  - R0210's review 007 found that the AC9 line itself named the index variable, which R0210's gate scans in every `check.sh`. The pattern is now written `"GIT_INDEX_""FILE"`: the shell joins the two halves, so the file never names the variable.
- F5: fixed. R0200.md now says that `prep-check-isolation` is R0210 (c0640, c0650, c0660).
