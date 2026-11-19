---
title: Keep the first error of every red before calling it unexplained
when: build
tags: [gate, flake, evidence]
check: Do I have the first error of every red I am about to call unexplained?
---
`ac.sh`'s `check` keeps only the last 25 lines of a failing command, and a command piped through `tail` keeps less. A red whose error was not kept cannot be explained afterwards, only rerun.

**Why:** On R0096 (2026-11-19) all six cases of d0298's `ready-order.spec` failed in one whole check, and a finish gate ended 1038 passed, 6 failed; both outputs had been cut to their last lines. Neither red came back in four later runs, and the code review could only rule causes out (review-001, answer (a)).

**How to apply:** Write the whole output of a check, finish or gate to a file (`> <scratch>/x.txt 2>&1`) and read from it. When something is red, rerun that one spec at once and keep everything it prints, before fixing or rerunning anything else.
