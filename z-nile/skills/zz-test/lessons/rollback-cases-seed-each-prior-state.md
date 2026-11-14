---
title: A rollback case seeds an item in each prior state the rollback must restore
when: both
tags: [rollback, fixtures]
check: In the failing case, does some item lack the file the command will write, and some item already hold the file it will modify?
---
A rollback that restores a modified file may leave a created one behind; a case where every item already has the file never sees it.

**Why:** c0263 design review 007 F2: `done` appends a `delivered` row; every member in the case already had a record, so a `done` that left a created file unstaged passed.

**How to apply:** seed one item per prior state (file present, file absent) and assert after the failed run that the absent one is absent again, then retry and count the rows.
