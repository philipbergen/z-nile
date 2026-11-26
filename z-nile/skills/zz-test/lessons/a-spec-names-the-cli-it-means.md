---
title: A spec names the CLI it means, never the one that runs the gate
when: build
tags: [specs, cli, environment, model]
check: Does every spec that calls `./zn model` (or anything that learns the AI CLI) pass `--cli <name>` or set the variable itself, so it passes the same in a plain terminal, in CI and in any other CLI?
from: the fix of c0435's light-path case (branch cli-env), found by a worker on another AI CLI, 2026-11-23
---
`./zn model` learns the CLI from `--cli`, else `ZN_CLI`, else a session variable (`CLAUDE_CODE_SESSION_ID`, `KIMI_SESSION_ID`, `GROK_SESSION_ID`). A spec that leaves all three out passes only inside the CLI whose variable is set, and exits 2 for everyone else.

**Why:** c0435 review 3 G ("a ticket captured with risk: easy resolves its design model at the easy level") ran `zn model design --for c0010` with no `--cli`. It passed for every session inside Claude Code and failed for a worker on another CLI, a plain terminal and CI.

**How to apply:** the runner now clears `fence.CLI_VARS` (the three session variables and `ZN_ACCOUNT`; `ZN_CLI` is on `fence.STEP_VARS`) for every spec, so such a spec fails for everyone. Name the CLI in the spec: `--cli claude`, or the variable in that command's own environment. Keep `fence.CLI_VARS` equal to `modelcmd.SESSION_VARS` (model-cmd.spec asserts it).
