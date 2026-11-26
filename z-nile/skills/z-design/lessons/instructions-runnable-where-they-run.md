---
title: Instructions must be runnable where they are read
when: design
tags: [skills, worktrees]
check: Can every agent told to do this do it from where it runs and in the role it has (a read-only main checkout, a capture that lands only issue documents, a reviewer or stream subagent that may not publish), and without breaking a project rule? And does every step that runs specs before the issue's code exists name the cases expected to pass then, and what a failure means? And does every experiment the design records name the exact bounded command it was run with (`./zn run --time <s> -- ...`), in the design and in the script's own header? And can a fresh session that resumes the work (a `./zn dispatch retry`, a new terminal) apply the rule from what is on disk and on origin, or does it lean on a memory of "what you did" that only the first session had? And can a tester perform every Observed step with what exists at the issue's time (the state a step needs reachable, by a command-bar line or a seeded record), rather than a state only a later issue produces? And is every sequence the skills tell the user to follow (rule, record, confirm) accepted by the command's own guards, such as a binding to the record the last round judged, run literally by a case?
---
An instruction added to many skills has to fit each skill's context. Writing a file is impossible in the main checkout, cannot land through a capture, and is forbidden to a reviewer. Where the action cannot happen, route it to something that can land (an issue, the author's harvest).

**Why:** R0040 design review 1 (F5): every skill was told to write lesson files when it finished, but only the prep and raft worktrees can carry them.

R0040 design review 2 (F3): the fix routed those skills to `./zn new issue`, which subagents (stream implementers and reviewers, handed the same skills) may not run. Skills are read by agents in different roles, so the split has to be by role, not by skill.

R0040 design review 3 (F1) found the fix still split by skill: one agent follows several skills at once (a prep author reads the design skill and the zz-test skill), so two skills gave it contradictory instructions. The rule that held was one paragraph, identical in every skill, keyed on role.

**How to apply:** for each skill a change touches, name every role that reads it (lead, stream subagent, reviewer), its working directory and what it may write or publish. Write one instruction keyed on role, the same wherever it appears, rather than a variant per skill.

c0120 code review 001 F2: the build's redo list said "rebase onto c0114, re-run the classification for new captures", which leaves out the `done`s the freeze and Guess 4 (a) put on main first (R0034, R0012, with their promoted pickman folders). Rebasing over them conflicts inside the renames-only commit. Redo steps for a stacked build start from the stop conditions and regenerate mechanical commits on the new base instead of rebasing them.

Every "ask the user" in a step a dispatcher can run needs its headless reading (R0052 code review 001 F5): z-design and z-raft still said "ask before merging the prep", which a headless agent turns into a stop at `questions.md` before the very gate the user decided it should pass. Grep the step's skill for each ask and say what the dispatched step does instead.

f0126 design review 008 F3: step 1 ran f0126's touch specs "first", on dependency code without any f0126 code, where 10 of 13 cases must fail, and also said to stop on any failure.

Run the replacement instruction on the failure it answers (c0263 design review 009 F3): a text changed from "resolve it with git merge" to "run ./zn sync" looped, because the sync that aborted left nothing to resolve; after the abort, can the user do what the text says, and does the next command then succeed?

Whose operation it is (c0263 design review 013 F1): a stop message in a helper that can be called while the user's own git operation is in progress must give the advice that fits that operation: "commit or stash" is right for a merge the helper started and aborts, and wrong for the user's hand merge (a commit keeps git's wrong pairing, a stash discards the merge); in each state that reaches a stop message, follow the advice and check the next command.

**Note (c0270 design review 001 F1):** a rule that called a `preparing` claim "another prep" unless "you made it" sent every dispatched retry of a prep to `questions.md`: the retried session made nothing yet, and nothing records who made a claim. Say what a resuming session reads instead (the dispatcher starts z-design on a claim only after its own chain's z-design step).

**Note** (c0226 design review 001, the reviewer's candidate): an inline shell recipe an agent is told to type runs in the agent's shell, which is the user's (zsh here), not bash. `for v in $(compgen -e …)` fails there with `compgen not found` and silently loops over nothing. Ask: does every inline recipe in a step or experiment run under the shell it was written for (`bash -c '…'`, or a script with a bash shebang)?

- f0208 design review 001 F5: OC1 asked for the purchase screen "on a later visit", but nothing in the portal uses a free start and the game place that does was not built yet, so a playtest always found the free start due. The step now claims it with a server command-bar call (`Wallet.arrive`) first.

**Also:** f0399 design review 001 F10 (2026-11-16): "the person runs `./zn approve <id>` in the raft's worktree" left out which layer the worktree is on and who pushes, and the specs pushed by hand. Say the branch, the tree's state and what reaches origin for every command the design hands to a person.
