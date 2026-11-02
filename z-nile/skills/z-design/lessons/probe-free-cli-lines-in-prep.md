---
title: Probe a CLI's command line in prep when the probe is free
when: design
tags: [cli, experiments, unknowns]
check: For every command line the design takes from a CLI's help without running it, can it be tried in prep at no cost (its help for the subcommand, or a call that the CLI refuses before it spends anything)? Has that been done, and is "unproven, Phase 1" left only for a probe that really costs something?
---
An unproven command line left for execution's Phase 1 carries a wrong guess through every review round, and the executor finds it only when the design is approved and the code built around it.

**Why:** c0117's three remote runtimes (`claude --cloud … -p`, `grok agent … headless`, `agent worker`) were left "unproven, Phase 1, with the user's consent to spend a probe" through five design rounds and a built implementation. Asked to decide G8, the user asked why the probe couldn't run at design time: `grok agent headless --help` and `agent worker --help` showed neither takes a prompt, and `claude --cloud … -p` refused before starting anything. All three were wrong, at no cost; the user split them into c0142.

**How to apply:** for each unproven CLI line, read the subcommand's own help and try the call with a flag set that fails fast (the CLI validates its options before it spends anything); record the result as an experiment. Leave for Phase 1 only what needs a real, paid run, and say what it costs.

Keep the probe free when the guess might be right (c0117 design review 006): a call that succeeds starts the paid thing (`claude --cloud` without `-p` opens a cloud session). Prefer the subcommand's own `--help`; run any real call through `./zn run`, in a scratch folder outside the repository, with flags that make the CLI refuse before it spends.
