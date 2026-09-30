---
id: c0400
type: chore
title: Raft browser
raft: 
depends_on: []
emergent: false
design: draft
created: 2026-09-29
---

# c0400: Raft browser

## Problem
The tracker is only browsable as directories and `tracker.sh list` output. The user wants to **see and navigate rafts and issues in a browser**: what's active, what's prepped (design ready), what's waiting, and how rafts depend on each other.

Requested (user, 2026-09-29):
- A tool that runs and **produces a self-hosted single-file web app** (one HTML file).
- A list of the **top-level rafts**: those without dependencies. **Cursor keys** move up and down the list.
- A **detail pane** for the selected raft: its document, its **reverse dependencies** (the second-level rafts that depend on it), and all its issues.
- **Stable ordering**, so regenerating from the same data produces the same page.
- Rafts and issues rendered nicely with a **JS Markdown renderer**. The user chose a vendored copy inlined into the page, so it works offline.
- **Status shown** for each item: active, prepped (design ready), reviewed, draft, done, and so on.
- **Tabs** at the top to filter: **done**, **active**, **waiting**.
- A **search field**: type any `c`/`d`/`f`/`R` ID to jump to the raft that holds it, with that issue highlighted.

## Non-goals
- Editing tracker state from the page: it's read-only.
- A live server or file watching: regenerate to refresh.
- Showing review files and spend in detail (a later chore can add them).

## Solution
Ideas: a `scripts/tracker.sh board [--out path]` command, which writes to a gitignored path such as `.cache/board.html`. Data is embedded as JSON, sorted by ID. Raft dependencies are derived from member issues' `depends_on` that point into another raft. The renderer is vendored under `scripts/vendor/`. (Design happens in ticket-prep.)

## Design
<!-- Modules and paths, public types and signatures, data flow, pure Logic vs adapter split,
     client/server authority. Must agree with the raft's whole-raft design and tracker/architecture.md. -->

### Scalability
### Maintainability
### Usability

### Touched modules
<!-- One backticked repo path per bullet (file or directory prefix), INCLUDING this issue's spec
     paths (e.g. `tests/unit/Maze`). Used for spend attribution
     and for `lune run scripts/affected -- <paths>` to list the affected specs below. -->

### Affected specs
<!-- Output of `lune run scripts/affected -- <touched paths>` plus the new specs. -->

## Unknowns & experiments
<!-- Per unknown: E1 question (pass/fail), how it is tested (experiments/E1-*.luau or a command),
     result if already run during prep, and the fallback design if it fails. -->

## Regression guard
<!-- Existing behavior/specs that must stay green, and new regression specs added here. -->

## Test plan
<!-- Spec file :: case -> AC number. Write these first; they must fail before implementation. -->

## Acceptance criteria

### Checked
<!-- ACn: statement. Each maps 1:1 to a `check "ACn: ..."` line in check.sh. Deterministic. -->

### Judged
<!-- Only if genuinely subjective. JCn: statement + rubric (what pass/fail looks like).
     Ruled on by the adversarial code reviewer. -->

### Observed
<!-- Minimal Studio playtest steps for the human (OCn). -->

## Implementation steps
<!-- Ordered, small, each verifiable. -->

## Verification log
<!-- Appended at the end of execution: date, commands run, results. -->
