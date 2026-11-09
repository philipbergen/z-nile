# Refute 005 (the final round; its high is answered below and goes to the user with the report)
- F1: fixed: every failure case writes its own page (no case reads a page an earlier one wrote), `boardModel` asserts the page exists first, each case asserts its own note text, and the sync under a vanished document asserts the rebuilt page and its note; mutants V1 (no page when a read failed) and the earlier survivors fail on assertions; consequences: none
- F2: fixed: the shim logs pushes beside fetches; the sync case counts fetches of main under any spelling, a new land case counts them after the push to `refs/heads/main` (exactly the land's own); mutants Mh and V10 (run); consequences: none, the cases use a capture worktree and the main checkout, so no later layer's beat or discard touches them
- F3: fixed: a clone with its origin removed reads nothing and says nothing; mutant V5 (run); consequences: none
- F4: fixed: the note has its own element above every view; mutant V11 (run); consequences: none
- F5: fixed: section 1, the c0118 row, Usability, AC2 and AC4 (the README sentence is added and grepped) say what the prototype does; consequences: none
