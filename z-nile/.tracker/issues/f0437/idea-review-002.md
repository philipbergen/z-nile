# Idea review 002

## Findings

- F1: The non-goal "The app never shows code" is broken by the fourth Solution line. A worker or dispatch run watched in an embedded terminal is an AI CLI writing code, and its terminal shows the diffs and file contents it edits, so the delivered app does show code. As written, the fence is false. The owner's ruling recorded in f0425 is "everything except look at code", which forbids a place to browse or read code, not a terminal that happens to print it. The non-goal needs to say which of those two it rules out, or else the embedded terminal goes against it.

## Verdict

revise
