---
title: A rule that names a program is checked against what ps prints for it
when: both
tags: [reaper, process-names, platform]
check: For each program a process rule names, did someone start it on the supported host and read `ps -o command=`, and does a case use that real spelling (a framework path, an app bundle, a login dash)?
---
A rule keyed on a program name only works if the name is what the host's `ps` prints. A prototype that was proven against `perl` and `sleep` said nothing about an interpreter that runs under another name.

**Why:** R0079 code review 001 F1: on macOS every `python3` (Homebrew, Command Line Tools, python.org) runs as `.../Python.framework/.../Python.app/Contents/MacOS/Python`. The reaper's name rule returned `Python`, which was in no list, and its application test excluded the path, so an orphaned Python (and a `lune` below it) was never stopped.

**How to apply:** start each named program on the supported host, copy its `ps` command line into the spec, and map or exempt the exact form that differs. Put the real spelling in a case that fails if the mapping is dropped.
