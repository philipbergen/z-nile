# Idea review 001

## Findings

- F1: Problems 2 and 3 are false as written. Problem 3 says "no such raft can pass `./zn trace <R-id> --check`", but the check can be passed today. The code cell is checked only against the whole stack's changed sources (`z-nile/engine/trace.luau:1126`), with no check of which ticket changed the file. So a tests-only ticket's claim passes if it cites a line the source-changing ticket changed. A lone "None." claim also passes: its design cell cites the "None." line in the ticket's own document, its test cell any green check line, and its code cell any changed source line. The real defect is that the check can only be passed by citing lines that don't support the claim. As written, a reader who tests Problem 3 would find it false, and the Problem doesn't say what is actually wrong.

## Verdict

revise
