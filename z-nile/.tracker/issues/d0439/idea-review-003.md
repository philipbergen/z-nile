# Idea review 003

## Findings

- F1: The Problem and the Solution both assume a signal ends the commands ("the signal behind it", "the signal and the cause are confirmed"), but that hasn't been established. On macOS, signal 16 is SIGURG, which processes ignore by default, so a command would not normally die from it. Exit code 144 may not come from a signal at all: the CLI could report that code for a command it ended itself, or a process could exit with 144 on its own. If no signal is involved, a reader can't judge "the signal is confirmed" true or false, and the Solution can't be met as written. Name what has to be confirmed without assuming its kind: what ends the commands and why, whether or not it is a signal.

## Verdict

revise
