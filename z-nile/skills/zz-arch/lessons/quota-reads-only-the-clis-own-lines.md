---
title: A quota or wait is read only from the CLI's own error lines, never from its logs
when: design
tags: [cli, quota, adapters]
check: Can text the model produced (a command it ran, a file it printed) reach the stream the adapter scans for quota and wait words, as when the CLI's logs quote the model's commands on stderr?
---
c0117's rule is that only the CLI's own words count as a quota wait. A verbose log stream on stderr quotes the model's own commands and outputs, so a quota word inside them would be taken as the CLI reporting a quota.

**Why:** c0175 design review 001 F4 (2026-11-15). opencode's `--print-logs`, added to see a tool call start, writes INFO lines that quote the model's commands to stderr. The runner's quota and wait checks read that stderr, and every spec fed `finish` an empty stderr, so none showed the leak.

**How to apply:** feed the log lines only to the liveness check, and the quota check only the CLI's own error lines. Add a case where a log line carries a quoted quota word and is not taken for a wait.
