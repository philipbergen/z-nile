---
title: A library change selects no dependent home's place spec
when: both
tags: [affected, places, arcade, gate]
check: For a change under `arcade/src`, does `lune run z-nile/affected -- <those paths>` list any other home's place spec, and if not, were those place specs run by hand (or left to the merge's full gate on purpose, said so in the plan), rather than "no specs affected" read as a pass?
---
The "Places" rule says a spec that loads a home's place is selected when its watch names what the place is built from, every `$path` included. Every home's `tests/place/library.watch.txt` names the homes' `.luaurc`, project files and `tests/lib/place.luau`, but no path under `arcade/src`, though every place maps `../arcade/src/shared` and `../arcade/src/server`. So `z-nile/check.sh --affected` on a library change prints "no specs affected" for portal, snake, invaders, asteroids and pickman, and only the merge's `--full` gate builds their places with the change.

**Why:** R0127 (f0395) review-001: f0395's step 7 relied on `z-nile/check.sh --affected` for "every home's place builds the library", and the executor's Verification log reported the other homes' "no affected specs" as if they had passed. The reviewer ran the place specs by hand (portal, snake, invaders, asteroids `library.spec` 2 passed each; pickman `library`, `structure`, `resolver` 8 passed).

**How to apply:** after a change under `arcade/src`, run each dependent home's place specs by file from that home (`cd <home> && lune run tests/run -- tests/place/library.spec.luau`; pickman's place folder holds more), and record the counts. Never write "the other homes had no affected specs" as evidence that their places build. A design that names `--affected` as the check that every place builds the library is wrong until the watch files name the library's paths.
