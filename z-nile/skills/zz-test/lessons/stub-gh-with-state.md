---
title: A gh stub keeps state
when: both
tags: [fixtures, gh, stubs]
check: Does the fixture's `gh` stub remember what earlier calls made (a PR exists once `pr create` ran, its base and body, its comments), so that a missing "reuse the open PR" or a comment on the wrong PR changes what the spec sees?
---
A stub that answers every call the same way (empty, or success) cannot tell a command that reuses an open PR from one that opens a second one, or a comment on the right PR from one on another.

**Why:** c0250's prototype: only once the `gh` stub recorded created PRs and comments could the spec kill the mutants "start does not reuse the parked PR" and "the comment goes on another PR".

**How to apply:** have the stub keep a small state file per PR (number, head, base, body, comments) and answer `pr list`, `pr view` and `pr comment` from it; assert on that state.
