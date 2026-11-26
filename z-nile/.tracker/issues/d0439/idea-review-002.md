# Idea review 002

## Findings

- F1: The Problem sentence says "exit code 144 (SIGTERM)", but those two don't match. A shell reports a signal death as 128 + the signal number. SIGTERM is 15, so it gives 143. Code 144 is 128 + 16, which is SIGURG on macOS and SIGSTKFLT on Linux. Read as written, the sentence is false, and the search for the cause would start from the wrong signal. The Problem should give the exit code actually seen and the signal it really maps to, or say which of the two was observed and which was assumed.

## Verdict

revise
