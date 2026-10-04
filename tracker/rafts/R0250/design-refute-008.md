# Refute 008: R0250 design review 008

- F1: fixed: land.spec's scope case gained two edit (`M`) sub-cases that only the path rule refuses: an edit to a draft raft document already on origin (`tracker/rafts/R0900/R0900.md`, which kills the "reuse `publish.allowed`" mutant), and an edit to `tracker/templates/issue/doc.md`, which carries `design: draft` (it kills the "frontmatter decides" mutant). The Rules row names both mutants.
- F2: fixed: f0600 on origin now has `status: prepared-a-b-c`, and a sub-case demotes it to draft and rewrites it with the status untouched. That is refused by the "draft on origin's side" rule, and the Rules row names the one-side mutant.
- F3: fixed: history.spec asserts that c0040, first seen in `done/`, has no spells, with a Rules row.
- F4: fixed: c0780's design rewords "The direct-push exception" as a whole. The status-only clause covers `tracker.sh`'s status publishes, a new clause covers `tracker.sh land` (edits to draft issue documents, design and status unchanged, after a local full gate), designs, reviews and specs never ride it, and the bullet stays one line with `tracker-only`.
