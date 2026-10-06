---
name: launch-raft
description: Start executing a readied raft in this session ("launch R0001", "/launch-raft R0001"). Reads the raft's prompt.md, enters the raft's worktree and follows the prompt. Fails when the raft isn't readied or has no prompt (run /ready-raft). Use for "launch R0001", "/launch-raft".
---

# Launch a raft

Start the session in the main checkout, which stays on `main`. The skill takes a raft id `<R>`.

1. **Read the prompt.** Run `scripts/tracker.sh prompt <R> --path`. If it fails, stop and report its message: the raft isn't readied (run `/ready-raft <R>`), or the prompt is missing (run `/ready-raft <R>` again to regenerate it). Never reconstruct a prompt by hand.
2. Read the whole file at that path with the Read tool, in chunks if needed. Don't print it through Bash: the output would be truncated.
3. **Enter the worktree.** The prompt's hard rule 2 says to run `cd "$(scripts/tracker.sh worktree <R>)"` first. From then on, work only there, and give subagents absolute worktree paths. The hooks follow the session's current directory, so they act in the worktree.
4. **Follow the prompt** as your instructions, from its first line: the execute-raft protocol, through the merge.

Other agents (Grok, ...) get the same text from `scripts/tracker.sh prompt <R>`.
