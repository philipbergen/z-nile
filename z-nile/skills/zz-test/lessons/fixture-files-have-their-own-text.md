---
title: A fixture that deletes or renames files gives each file its own text
when: build
tags: [fixtures, git, renames, deletions]
check: Do any two files this fixture deletes and adds share their text (a `return {}` placeholder, say), so that git reads the pair as a rename? And did the case fail by assertion on the code before the fix?
---
`git diff --name-only` detects renames by default. A fixture that deletes one file and adds another with the same text (placeholder files are the natural fixture text) is read as a rename, and only the new path is listed: the deletion the case is about never happens, and the case passes on the code it should fail on.

**Why:** d0410 (R0125, 2026-11-17; R0125 code review 001 F2): the first draft of `z-nile/tests/tooling/finish-deleted.spec.luau` deleted `Old/init.luau` and added `Maze/init.luau`, both `return {}`. Its "a deleted source is in no list" case passed on the unfixed `./zn finish`, because finish saw a rename, not a deletion. Running the case on the old code first caught it; the fixture now gives each source its own text.

**How to apply:** give every file a deletion or rename fixture adds or removes a text of its own (`return { old = true }`), and run each new case on the unfixed code to see it fail by assertion before writing the fix. zz-arch's deleted-files-come-from-a-no-renames-diff is the same git behaviour from the reader's side.
