---
title: A PATH folder a hook puts first holds only the shim
when: design
tags: [hooks, path, shim]
check: Does any other program in the folder a hook puts first on PATH shadow a system tool, and was the stand-in project in the spec a copy of the real folder, with git, gh and a read-only ./zn command run after the env file was sourced, in an interactive and a dispatch-shaped environment?
---
A SessionStart hook that writes `export PATH=<dir>:$PATH` to the session's env file changes every command of every session. If `<dir>` already holds other programs, they shadow the system's.

**Why:** R0070 code review 001 F1 (c0194): the shim went into `z-nile/bin`, which already held c0117's dispatch-only `git` and `gh` wrappers (they exit 2 outside `./zn dispatch`). The spec's stand-in project copied only `mktemp`, so every check passed while every real session would have lost git, gh and `./zn`.

**How to apply:** `ls` the real folder before choosing it; give the shim a folder of its own, or make the spec's stand-in a copy of the real folder and run `git --version`, `gh --version` and a read-only `./zn` command after sourcing the env file, plus a dispatch-shaped environment (main's wrapper folder first must stay first).
