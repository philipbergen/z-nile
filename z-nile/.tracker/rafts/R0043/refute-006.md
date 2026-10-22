# Refute 006: R0043
- F1: fixed, as the coordinator directed. R0047 is being prepped on main right now, so it is not moved on this branch now; the move would conflict with that prep. Instead:
  - `./zn audit` reports `error raft-spans-projects` for an unfinished raft whose member sits in another root, reading membership both from the raft's `issues:` and from each issue's `raft:`.
  - Finished rafts are exempt, because R0001 spans two roots by decision.
  - It is pinned by `tests/tooling/audit-raft-roots.spec.luau`, a `.cache` fixture with four cases: a listed z-nile member, a member linked only by `raft:`, a same-root raft, and R0001's finished shape. Mutants R113 (the error dropped), R114 (the `done/` exemption dropped) and R115 (the `raft:` side ignored) are each killed.
  - Step 9 now runs `./zn audit` after the final merge of main and moves each cross-root unfinished raft, R0047 by name, with its members' root in its own renames-only `c0114: move` commit listed under JC1. The design (§4's audit row, step 9, the Rules rows) and #98's description say so.
  - The reviewer's lesson is written as tracker/audit-what-new-refuses ("Every rule `new` enforces is also an audit error for items that arrive by merge").
  - consequences: the real tree audits clean today (`0 errors, 1 warnings`). After the next merge of main it reports R0047 until step 9 moves it, which is the intent. Until then AC12 and RC2 go red on that merge, so the landing merge and the move go together.
- F2: fixed: the offline message now says "fetch (./zn sync --fetch) if c0114 has landed", and window-new-raft.spec's needle matches. window.spec's sequestered needle ("capture from the main checkout until it does, never offline here") is still in both messages, and window.spec passes.
