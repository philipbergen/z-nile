# Refute 003 (answers review-003, layer 4)

- F1: fixed 1f7eea09c: the pinned stylua formats `hb.readBeats` in layer 1 (formatting only), the stack was rebuilt on it, and the affected gate was run per layer (layers 1, 3, 4, 5 green); consequences: no behaviour, spec or watch-map change; the lower layers' commits are rewritten, so the draft PRs were force-pushed with a lease.
- F2: fixed a75d01dac: the stale comment above `buildBoard` is replaced, the README says `./zn status`'s verdicts, and c0276's Verification log records that the notes are drawn in `#notes` above every view (not `#problems`); consequences: none (comment and text; AC4's pinned words `lost 35m`, `no beat`, `lost work comes first`, `c0276` are untouched, and `./zn check c0276` was rerun).
