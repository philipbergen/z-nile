---
name: ready-raft
description: Ready a raft for execution, which claims it, moves it and its issues to `active/` on origin/main with their `check.sh` paths rewritten, and writes the self-contained prompt to `tracker/rafts/active/<R-id>/prompt.md` for any agent (Opus, Grok, ...) to deliver as one PR. An issue with no raft goes back to ticket-prep first. Also used to regenerate the prompt. Use for "ready a raft", "ready R0010", "/ready-raft".
---

# Ready a raft

1. **Resolve the target.** Given an issue ID, the target is its raft. If the issue has no raft, stop: ticket-prep makes one (`--single` for a lone issue) in its prep worktree and merges it. A prompt for an undesigned issue defeats the purpose.
2. **Check readiness.** `scripts/tracker.sh ready` enforces every rule below except the acceptance specs one, and refuses with the reason, naming the item; read them so you can explain a refusal.
   - The raft and every member are `design: ready`.
   - Every issue has a `check.sh` with at least one `check`.
   - The acceptance specs that each `check.sh` names exist. `ready` doesn't check this one, so look before you run it.
   - `scripts/tracker.sh status <R-id>` prints `prepared`: the prep PR has merged and main is current.
   - Every `depends_on` of a member issue that isn't a member of this raft names an item in `done/` (`scripts/tracker.sh find <id>`), for example the chore that removes a promoted spec the issue overrides. If one isn't, stop and say which.
   - The executing agent starts from origin/main, so it must see the same files.
3. **Ready it.** In the main checkout, run `scripts/tracker.sh sync` first, then `scripts/tracker.sh ready <id>`. It checks the main checkout is on `main` and clean, claims the raft, and publishes one tracker-only commit that moves the raft and its issues to `active/` on `origin/main`, with every item path in their `check.sh` files rewritten. It then pulls the main checkout (a fast-forward) and writes `tracker/rafts/active/<R-id>/prompt.md`, which git ignores.
   - The prompt fills in `tracker/templates/prompt.md` with the raft and issue documents, the `check.sh` files, the sequestered acceptance specs, the architecture map and the `execute-raft`, `tracker`, `architecture`, `testing` and `review` skills.
   - The design-review history isn't inlined. Its outcomes are already folded into the documents.
   - Running it again on an active raft regenerates the prompt from the current documents and makes no commit.
4. **Report** the character count and a 3-line outline: mission, issues, and the number of Checked criteria, plus the plan's last line (`parallel: yes` or `parallel: no`, from `tracker.sh workstreams <R-id>`). The next step is `/launch-raft <R>` in a Claude session started in the main checkout, which enters the raft's worktree (`scripts/tracker.sh worktree <R>`) itself.

To change what every prompt contains, edit `tracker/templates/prompt.md` or the skills. Don't hand-edit individual prompts.
