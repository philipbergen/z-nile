# Idea review 001

## Findings

- F1: The idea never says what happens to the specs that load engine modules directly instead of running the command. In `z-nile/tests/tooling/`, 55 of the 111 specs `require` engine modules. Those specs cannot run against the Go program, so "its specs pass on both" can't be true or false for any command they cover. They also stop working when the change that switches a command deletes its Luau form. The non-goal "does not convert the specs that are not unit tests" hints that unit tests do get converted, but no Solution sentence says so. As written, the idea allows a command to switch with only part of its specs run against Go, and with the rest deleted or left broken.

## Verdict

revise
