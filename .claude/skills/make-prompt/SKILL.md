---
name: make-prompt
description: Produce the self-contained execution prompt for a raft (or a single issue, which gets a placeholder raft) and copy it to the clipboard, for any agent (Opus, Grok, ...) to deliver as one PR. Use for "make a prompt", "prompt R0010", "/make-prompt".
---

# Make a prompt

1. **Resolve the target.** Given an issue ID, the target is its raft. If the issue has no raft, `tracker.sh prompt` creates a placeholder raft (`--single`).
   - In that case, check that the issue went through `ticket-prep`. If it's still `design: draft`, stop and run ticket-prep on it first. A prompt for an undesigned issue defeats the purpose.
2. **Check readiness.**
   - The raft and every member are `design: ready`.
   - Every issue has a `check.sh` with at least one `check`.
   - The acceptance specs exist.
   - `git status` is clean for `tracker/`, and main is pushed. The executing agent starts from origin/main, so it must see the same files.
   If a placeholder raft was just created, commit and push it (`tracker: placeholder raft R…`) first. Ask the user if they haven't approved direct commits to main.
3. **Render**: `scripts/tracker.sh prompt <id>`. This fills in `tracker/templates/prompt.md` with the raft and issue documents, the `check.sh` files, the design reviews, the architecture map and the `execute-raft`, `tracker`, `architecture`, `testing` and `review` skills, then pipes the result to `pbcopy`.
   - **No file is written.**
   - Use `--stdout` to inspect it instead.
4. **Report** the character count and a 3-line outline: mission, issues, and the number of Checked criteria. Tell the user it's on the clipboard.

To change what every prompt contains, edit `tracker/templates/prompt.md` or the skills. Don't hand-edit individual prompts.
