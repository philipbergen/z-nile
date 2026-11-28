# Refutes 003: c0460
- F1: fixed: the Design bullet for step 4 now says "reached only through `./zn` or `lune run` commands and the files they read and write", the words the spec pins; consequences: none.
- F2: fixed: the check reads "lists nothing but `mutants.md` and any kill case written for a survivor"; consequences: none (the Phase 2 pin looks for `git status --porcelain` and `commit the layer`, both still present).
