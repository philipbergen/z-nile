---
title: A fixture ignores what the repository ignores
when: design
tags: [fixtures, specs, guards]
check: Does each fixture repository carry the `.gitignore` lines the real one has for the files the commands under test write (`prompt.md`, `.cache/`), so that a guard that compares `git status` before and after sees what it sees in the real checkout?
---
A guard that compares the main checkout's `git status` (the dispatcher's tripwire) counts any file the step writes that is not ignored. A fixture without the real `.gitignore` turns an ignored file into a change, and the guard stops a run that would pass in the repository.

**Why:** c0250's prototype (prep, 2026-11-13): a dispatched `block` of a readied raft tripped the dispatcher's main-checkout tripwire in the fixture only, because `ready` had written `prompt.md` there and the fixture did not ignore it.

**How to apply:** copy the relevant `.gitignore` lines into every fixture that runs `ready`, `stop`, `block` or a dispatched step, and say in the spec which real line each one mirrors.
