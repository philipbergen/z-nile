# Answers to design-review-006 (c0184)

Verdict approve, three lows.
- F1: fixed: the Rules and mutants table gains a row for the widened promoted rules (c0114 and c0120 docs, c0115 layout, docs and absence; mutants run by review 006, killed) and one for the doubled and unclosed deps-block cases (run, killed). Consequences: none.
- F2: fixed: the leftover sentence "Neither is digest-pinned by c0172's narrowed.spec" is deleted; the paragraph above it states the one digest.
- F3: fixed: check.sh AC9 lists c0115 `docs.spec` and `absence.spec` once each. `bash -n` and `AC_LIST=1` list the same nine criteria.
