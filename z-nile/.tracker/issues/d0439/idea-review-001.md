# Idea review 001

## Findings

- F1: The Solution is bigger than the Problem. The Problem names only `./zn idea` and the other commands of the session that started it. The Solution's check covers "any `zn` command that starts a nested AI session" and commands of "another session" in general, which takes in unrelated CLIs on the machine, and the Problem gives no evidence for either. The smallest solution confirms and records the cause, then checks that a `./zn idea` run never stops a command of the session that started it. The wider claim needs its own observed problem first.

## Verdict

revise
