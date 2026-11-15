---
title: A lesson harvested from a code review is marked for the build stage
when: build
tags: [harvest, lessons, stage]
check: Does each lesson written from a code or final review say `when: build` or `both` (not `design`), so the search an executor runs while building finds it?
---
`./zn lessons` shows a lesson at the stage it names; a lesson written from a review of built code and marked `design` is never shown to the executor who would make the same mistake.

**Why:** R0100 final review F9. Five lessons written from code reviews were all `when: design`, and the build-stage search listed none of them.

**How to apply:** when writing a lesson from `review-NNN.md`, set `when: both` for a rule a designer and a builder can both break, `build` for one only a builder can; write `design` only for a flaw in what a design says.
