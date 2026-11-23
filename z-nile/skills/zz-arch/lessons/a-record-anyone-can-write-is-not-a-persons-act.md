---
title: A record any process can write does not prove a person acted
when: both
tags: [approval, signing, agents, trust]
check: Does the thing that makes an act 'the person's own' rest on something a process running as that person does not have (a touch, a hardware key, a second device), or only on checks in front of a command?
from: design review 001 of f0437 step 6a (Fable), 2026-11-22
---
Checks in front of a command (a terminal test, a hook, an environment marker) are hurdles: any process with the same account can step round them or write the record directly.

**Why:** the design review found the approval row is a plain line (date, git user name, hash) that any process can append and commit, and that the terminal check is passed by a script file, a new terminal window or a multiplexer. The owner's own words the same day: no safeguard inside one account fully stops an AI working round it.

**How to apply:** say plainly which protections are hurdles and which are guarantees. A guarantee needs a signature from something the agent lacks, verified where the act takes effect, plus a visible, revocable record.
