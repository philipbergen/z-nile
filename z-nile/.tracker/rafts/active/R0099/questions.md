## How should c0283 be re-prepared on c0369 before this layer continues?

c0369 landed on 2026-11-18 (`R0130: bind c0369`, in `done/`). c0283's Implementation steps say its approve delta (Behaviours 1, 2 and 4, the texts, and `acceptance/approve.spec.luau`) is re-prepared on top of c0369 before this layer, including the explainer-page fixture c0368 asked for. That re-prep has not been done: the document's last edit is c0369's note itself (2026-11-17), and the sequestered specs are unchanged.

Building the current contract cannot pass both checks. `c0283/acceptance/docs.spec.luau` requires z-design to say `in a terminal of their own in this worktree`. c0369's promoted `docs.spec` requires `in a terminal of their own, from anywhere in the checkout` and refuses `in this worktree` in the engine. c0369's Design section 7 lists the conflicts (the refusal text, the `approved` row beside the new one-command approve, `--publish`, the texts, and the approve specs).

An executor cannot make that re-prep: it edits the contract sections, which are hashed into `approval.md`. Section 7 also says R0099 must be unfolded first, because `grouped:` hashes c0283's whole document and a later `ready` would refuse it as redesigned.
