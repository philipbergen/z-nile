---
name: make-prompt
description: Produce the self-contained execution prompt for a raft (an issue with no raft goes back to ticket-prep first) and copy it to the clipboard, for any agent (Opus, Grok, ...) to deliver as one PR. Use for "make a prompt", "prompt R0010", "/make-prompt".
---

# Make a prompt

1. **Resolve the target.** Given an issue ID, the target is its raft. If the issue has no raft, stop: ticket-prep makes one (`--single` for a lone issue) in its prep worktree and merges it. A prompt for an undesigned issue defeats the purpose.
2. **Check readiness.**
   - The raft and every member are `design: ready`.
   - Every issue has a `check.sh` with at least one `check`.
   - The acceptance specs exist.
   - Run `git pull --ff-only` in the main checkout first, then check that `git status` is clean for `tracker/`: the prep PR has merged and main is current. (Read-only checks only: nothing is edited in the main checkout.)
   - The executing agent starts from origin/main, so it must see the same files.
3. **Render**: `scripts/tracker.sh prompt <id>`. This fills in `tracker/templates/prompt.md` with the raft and issue documents, the `check.sh` files, the sequestered acceptance specs, the architecture map and the `execute-raft`, `tracker`, `architecture`, `testing` and `review` skills, then pipes the result to `pbcopy`.
   - The design-review history isn't inlined. Its outcomes are already folded into the documents.
   - **No file is written.**
   - Use `--stdout` to inspect it instead.
4. **Report** the character count and a 3-line outline: mission, issues, and the number of Checked criteria. Tell the user it's on the clipboard, and give the launch line `cd "$(scripts/tracker.sh worktree R…)" && claude`, which starts the agent inside the raft's worktree.

To change what every prompt contains, edit `tracker/templates/prompt.md` or the skills. Don't hand-edit individual prompts.
