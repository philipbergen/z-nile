# Design refute 008: c0261

No review round precedes this file: it records the changes the user's answers of 2026-11-08 (the veto items) made after design-review-007, and the consequence step on each. The review of the result is design-review-008.md.

- Model cells: z-design is off the cheap model (claude `claude-opus-5-5` at medium, grok `grok-4.7` at high, agent `grok-4.7-high`, rank 3 as c0117 had it); z-run, z-ticket, z-raft and the wait cells are as proposed. Consequences: `.models.toml` z-design tables, the root-file spec's classes (a new "author" class; finals rank above every non-final activity) and exact names, the zz-rules bullet, the Design's cost note (the one extra expensive round per issue is the review's, unchanged); c0117's Overrides do not grow (z-design on Opus is closer to today); mutants "z-design back on the cheap model" runs and dies.
- Kimi: the final-review kinds are now `k3.1-pro` and `k3-256k` at high or max (the kimi CLI's ids, as `models.id` writes them), plus the agent CLI's `kimi-k3-high`/`kimi-k3-max` as stand-ins and a forward `kimi-k3.1-pro-high/max` by shape; `kimi-for-coding` (K2.8 Preview), `-low`, plain `k3` are not final kinds (a cheap-cell candidate for c0175's kimi table, not placed here). Probed (E1b): the kimi CLI's own config lists the ids; the agent CLI lists only the K3 ids. K3-256k as a lesser kind is a veto item. Consequences: `FINAL_SHAPES` has a `kimi` family, `isFinalModel` unions the families, the refusal text, the docs pins and the spec lists changed; mutant "kimi-for-coding accepted" runs and dies.
- Open questions 4 and 5 (nested review wait; run-PR merge) are answered and removed: "Accept the blocking wait" and "c0252 builds it"; the Design's waiting text says so.

## design-review-008: answers

The round holds one high (F1), so it is not answered into `ready`: the issue goes back to `design: reviewed` / `preparing` and the report goes to the user.

- F1 [high]: fixed in the texts and the sequestered docs case: the AGENTS.md sentence and docs.spec now say a hand-started lead takes the model `.models.toml` names for its activity (`/z-run` the cheap one, `/z-design` Opus at medium), the old wording has an `absent` case, zz-rules says the z-design session blocks and the user accepted it, and Open question 6 is rewritten. Not re-reviewed.
- F2 [medium]: escalated: Open question 9 (accept that the Opus-at-medium z-design blocks on each nested review round, the default, or end and resume it), a veto item; the Design sentence no longer says "still holds".
- F3 [low]: Open question 10 (agent's z-design cell is the author's mapping; `claude-opus-5-5-medium` is the other candidate).
- F4 [low]: Open question 11 (plain K3 through agent versus the kimi CLI).
- F5 [low]: fixed: the agent-fallback refusal text, the `.models.toml` header, E1's Haiku note, README:65; c0117's two comments on the agent tables (no running token count; the wall-time ceiling) are the executor's to restore in the root file.
