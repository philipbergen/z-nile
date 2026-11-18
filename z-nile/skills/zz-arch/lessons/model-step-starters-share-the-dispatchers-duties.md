---
title: Anything that starts a model session takes on every duty of the dispatcher's model step
when: design
tags: [dispatch, credentials, guards, spend]
check: Does this new starter of model sessions go through the dispatcher's step machinery (wrapper PATH, agent credential, publish broker, guard start and tripwire, measured spend row, gate merges), or else list each of those duties and show where it does them? Which of them would a session started outside it escape?
---
The dispatcher's model step is where the guards live: the `z-nile/bin` wrapper first on `PATH`, the agent's own credential, the publish broker, the guard start, `vetMain` and the tripwire, the measured spend row, and the `auto_merge` gates. A second starter that calls the CLI launcher directly gets none of them, and each gap is a separate finding.

**Why:** c0253 design review 001, F1 and its siblings (F2, F3, F6, F8). The supervisor called `modelstep.launch` itself. Its sessions ran with no wrapper, no broker and no tripwire while it held the person's credential to land. It dropped every session's spend row, and nobody merged the prep and rafting pull requests its sessions opened. The captured Solution had already said "a thin loop over … the dispatcher".

**How to apply:** start sessions through the dispatcher, adding what the new caller needs (such as a resumed session) to the dispatcher itself. If a separate starter is unavoidable, factor the step environment and the guard calls into one module both use, and pin each duty with a case.
