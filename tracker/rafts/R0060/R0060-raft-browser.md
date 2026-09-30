---
id: R0060
type: chore
title: Raft browser
single: true
issues: [c0400]
design: ready
created: 2026-09-29
---

# R0060: Raft browser

## Theme
A single-issue chore raft for c0400, which the user requested on 2026-09-29: a way to **see and navigate rafts and issues in a browser**. `tracker.sh board` generates one self-contained, byte-stable HTML page from `tracker/`. It has Active/Waiting/Done tabs of top-level rafts, keyboard navigation, a detail pane with dependencies both ways and rendered Markdown, and ID search with highlighting. It's tooling, with no change to the game, so it's a chore.

Decisions the user made in prep (2026-09-29), quoted in c0400's Problem, including three made after design-review-001 (Active from the directory only, only Waiting filtered, a node smoke test):
- top level means "no unfinished dependencies";
- unrafted issues appear under a "No raft" entry;
- the command is `scripts/tracker.sh board [--out PATH] [--open]`, writing to `.cache/board.html` by default;
- the Markdown renderer is vendored and inlined (marked 18.0.14, MIT).

## Whole-raft design
See c0400's Design. The shape:
```
tracker/{rafts,issues}/[active/|done/]<ID>/<ID>-<slug>.md
   │ board.collect(root)                 (statuses, raft deps both ways, top level, tabs, No raft, home)
   ▼
Model ──board.encode──▶ JSON (sorted keys, [] for empty, < escaped)
   │                              │
scripts/tracker/board.html ──render──▶ one HTML file ◀── scripts/vendor/marked.umd.js (sha256-pinned)
                                        │
scripts/tracker.sh board [--out] [--open] ──▶ .cache/board.html (gitignored)
```
- **Everything a test can check is decided in Luau.** The page script only renders the model and handles keys, tabs, search and hash links.
- **No change to `src/`, `tests/meta` or `tracker/architecture.md`.** `scripts/tracker/main.luau` gains one command and one boolean flag. The tracker skill gains one line.

## Order & dependencies
One issue. Its steps go vendor, model, page, CLI, docs. There are no dependencies: it reads the tracker layout that `store.luau` already defines.

## Experiments phase
All run in prep, all PASS:
- E1: marked vendored and inlinable, rendering in a browser-like sandbox.
- E2: Lune's sha256, and the empty-table JSON pitfall that led to the design's own encoder.
- E3: a prototype passing all five acceptance specs (28 cases), with 24 planted bugs caught.
- E4: the node smoke test driving the page script. After design-review-002 it also models load order and focus, presses every key, and covers a page with nothing active.

The executor has no Phase 1 work.

## Exit criteria
Implemented by `check.sh`:
- **RC0**: the full repo gate passes, c0400's `check.sh` passes (AC1–AC6, AC6 needing `node`), and `promote-check` passes.
- **RC1**: on the real tracker, `tracker.sh board` run twice produces identical files, and `git status --porcelain` is unchanged.

Observed: c0400 OC1, clicking through the generated page in a browser.

## Risks & rollback
- **Risk: marked's API changes.** It's pinned by sha256, so it can't change unless someone does it on purpose.
- **Risk: the page's JavaScript breaks in a browser.** AC6 runs it under node against a fake DOM with the designed API subset. What's left for OC1 is layout and clicks.
- **Risk: `node` is missing.** It's preinstalled on GitHub's runners and on this machine, and `SETUP.md` lists it after this raft. AC6 fails with a clear message rather than silently passing.
- **Known limitation (user decision)**: on `main` the Active tab is empty, because rafts are only in `active/` on their branch.
- **Risk: tracker documents with unusual frontmatter**, such as a missing field. `collect` defaults missing fields to `""` and false, and never errors on them.
- **Rollback**: revert the PR. Nothing depends on the board.

## Addressed during execution
