# Refute 015: c0115 (design mode)

- F1: fixed: freeze.spec adds a local branch named `origin/impl-c0115` holding its own "c0115: move the skills" commit (a branch cut from it is listed, the real move stays pinned) and an implementation commit whose subject only contains the words ("note: not c0115: move the skills"; the move stays the one). Mutants U (short refnames) and T (contains, not starts) killed; the G14 row lists them; consequences: none (the engine already used full refnames and a prefix match).
- F2: fixed: AC13's `moves_only` reads `git log --format='%H %s'` and keeps the commits whose subject starts "c0115: move the skills", never a body line, as the engine does; consequences: the subject is matched at a fixed column after a 40-character sha, which holds for this repository's SHA-1 object format.
- F3: fixed: `history-tests-survive-squash`'s `check:` asks the lookup question too (same range, subject only, nothing for zero or two); consequences: none.
