---
name: make-issue
description: Capture a new feature/defect/chore issue in the tracker backlog. Use when the user describes work to be done, a bug, or a chore ("add an issue", "we should", "bug:").
---

# Make an issue

0. **Open a capture worktree first**, before anything is created: `cd "$(scripts/tracker.sh worktree capture-<slug>)"` (tracker skill, Worktrees). Everything below runs there, never in the main checkout. Then run `scripts/tracker.sh sync`, so you see every item other terminals have created.
1. **Classify the work**:
   - **feature** (`f`): new player-facing or developer-facing capability.
   - **defect** (`d`): **game or product** behavior that's wrong compared with an issue that's already done or with an obvious expectation. This is rework, and it's counted against the 20% target, so classify honestly.
   - **chore** (`c`): tooling, refactors or infrastructure, with no change in behavior. **Anything related to CI or tests is always a chore, even when it's a bug**, for example:
     - a flaky or wrong spec, including a promoted acceptance spec;
     - a test-selector graph miss;
     - a broken gate script, `setup.sh`, hook or workflow;
     - tracker CLI bugs.
     These never count as rework.
2. **Create it**: `scripts/tracker.sh new issue <f|d|c> <kebab-slug> --desc "<one line>"`. The stub, with that line as its Problem, is pushed to `origin/main` at once, so other terminals see the id and the item. The slug is 2–5 words describing the outcome.
3. **Fill in the frontmatter**: `title`, and `depends_on` (IDs) if you already know them.
4. **Fill in only these sections**:
   - **Problem**: the user's words, sharpened. Who is affected, what happens now, and what should happen.
   - **Non-goals**: whatever came up and belongs elsewhere.
   - A few bullet-point ideas under Solution, if they came up.
   Everything else is left for `ticket-prep`. Keep `design: draft`.
5. **Duplicates**: look for overlaps with `scripts/tracker.sh list backlog`. If there's an overlap, say so and ask whether to merge.
6. **Land it.** Commit in the capture worktree (`git add tracker && git commit -m "tracker: new <id> <title>"`), run `scripts/tracker.sh land`, and before the worktree is removed record `scripts/tracker.sh spend <id> --phase capture --time <minutes>`, then remove the worktree with the command it prints. No PR: land runs the gate locally and pushes to `main`. Report the ID and path.
