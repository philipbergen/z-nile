# Refute 005: c0115 (design mode)
Answers `design-review-005.md`. Decided with the user (2026-10-21): one extra design round (6) past the cap; recorded in the Verification log. The base is unchanged: `proto-c0120` bc550e9.

- F1: fixed: the every-byte case is now one table in `lessons.spec`, with one row per part of a ledger: id list, note text, one-off reason, heading, paragraph, sub-bullet, refused line. Each row is checked twice:
  - with `testing/no-vacuous-pass` (its renamed lesson exists): `ledgerOldIds` finds it exactly once, and `renameLedger` renames it in place with a count of 1;
  - with a look-alike (`zz-test/fixtures` for the id list; `review/x`, `testing/fixtures` or `tracker/rafts/R0010` for prose): not found, and byte-identical with a count of 0.

  Two more checks: a one-off naming `testing/never-a-lesson` (no renamed lesson) is reported by neither function, so the script's exit stays 0; and a refused line still fails `parseHarvest` after its rename. M51 (one-off lines left alone, your probe) is killed by the one-off row. M46 to M52 were rerun with the runner, all killed; M49 now kills on the table's sub-bullet and paragraph rows. Consequences: none; the table is the list the next new part of a ledger must join (lesson zz-test/seed-every-enumerated-case).
- F2: fixed: `ledgerLine` now renames each id in place with a `gsub` over the id list. A chunk keeps its own leading and trailing spaces, untouched ids are returned as they are, and the head pattern no longer drops trailing spaces. A new case, "an id list keeps its separators and spaces byte for byte", covers three lists:
  - a `,`-separated list with trailing spaces, holding one rename;
  - a no-space list with no old id, on a line of a file that has renames, which comes back byte-identical;
  - a note list with spaces around a comma.

  M52 (untouched ids trimmed) is killed. On the overlay, the script's ledger output equals a pure substitution of the old ids (219 rewrites, a second run 0).
- F3: fixed: E5 says "(M1 to M52)". The script's header and its comment in `fix` now say "every other part of a ledger is prose (a note's text, a one-off's reason, and the lines parseHarvest skips or refuses)", matching §5.
