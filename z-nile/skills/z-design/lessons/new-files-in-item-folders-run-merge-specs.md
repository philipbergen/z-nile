---
title: A command that starts writing a file directly into item folders changes how git merges the folders beside it
when: design
tags: [merge, folders, overrides]
check: Does this command add a new file directly inside an item's folder, and have the promoted specs that move that folder (ready, stop, done) or merge main into a worktree holding it been run on the prototype?
---
Git's directory-rename detection fires for a file added in a folder the other side renamed, and it fires for the files nested below it too, but only once a file was added directly in the folder. A fixture that merged cleanly with a nested file alone stops with `CONFLICT (file location)` as soon as a direct child (a record) is added beside it, even when both sides hold the same bytes.

**Why:** c0282 prep E8: with the `rafted` rows, `c0084/spend-command` went red on its `new issue` steps; c0263's prototype, which adds no such file, passed. Probes: a nested file added on both sides merged clean, the same plus a direct child stopped on both.

**How to apply:** run the override batch on the prototype, not only the specs that name the command; read a red merge as the folder rule, and change the fixture to take the squash commit (`./zn sync`) before the folder moves, as a real worktree does.
