---
title: A spec's "terminal" clears the agent session
when: design
tags: [specs, fixtures, agents]
check: Does every spec environment that stands for a person in a terminal clear the agent markers and the session ids (`CLAUDECODE`, `AI_AGENT`, `ZN_DISPATCH`, `ZN_HEADLESS`, `CLAUDE_CODE_SESSION_ID`, `KIMI_SESSION_ID`, `KIMI_CODE_SESSION_ID`), and does a case that needs two sessions set two different ids explicitly?
---
The gate usually runs inside an agent session, so the spec's own processes inherit that session's markers and id. A "terminal" environment that clears only the markers still shares one session id between every command the spec runs, and a rule keyed on the session (a resolve refused from the session that filed the block) refuses the spec's own steps.

**Why:** c0250's prototype (prep, 2026-11-13): the promoted `c0117/control-cli` case "stops the chain at a blocked item" went red on the slow tier only: its fake step and its `resolve` ran with the gate's `CLAUDE_CODE_SESSION_ID`, and `resolve` correctly refused.

**How to apply:** build one `TERMINAL` environment that clears every marker and session id, and give each simulated agent session its own explicit id. Run the spec once from inside an agent session before calling it green.
