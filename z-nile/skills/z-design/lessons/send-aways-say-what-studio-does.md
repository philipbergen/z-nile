---
title: A rule that sends a direct join away says what it does in Studio
when: design
tags: [teleport, studio, playtest, regressions]
check: What does a Studio Play of this place do on its first run and on its second within the rule's window (with API access on and off), where teleports fail and a developer opens the place directly, and is there a case in test mode, not only live?
---
A place that refuses a player who did not come through the lobby (sending them back, kicking on a failed teleport) also refuses the developer. Studio opens the place directly and cannot teleport, so the developer's ordinary play-test loop becomes a kick, and every spec pinned in live mode stays green.

**Why:** R0118 code review 001 F2 (f0145): a "buy" arrival without the lobby's pass is sent back, and kicked when the teleport fails. With Studio API access on, the first Studio play took the hour's free start in the test store, and every later play within the hour was kicked with "Start a game from the lobby.". The design said test mode covers Studio, but none of its rules or cases looked at a direct Studio play, and every send-back case ran in live mode. Fixing it changes a user decision, so it went to the user at execution instead of at prep.

**An option that adds an engine read checks the stubs.** R0118 final review 001 F1: one option put to the user was "only in Studio" (`RunService:IsStudio()`), offered as leaving every sequestered case green. But the sequestered stub engine's `RunService` had no `IsStudio`, so a bare call errors in the live send-back cases and would have made that option an Override. An option that adds an engine read says whether every sequestered stub serves it, and if not, how the read is guarded (`pcall`, a missing method meaning "not Studio").

**How to apply:** for every rule that turns an arrival away, write what Studio does on its first and second play (API access on and off), put it to the user with the rule when it is decided, and pin the answer with a test-mode case whose teleport fails.
