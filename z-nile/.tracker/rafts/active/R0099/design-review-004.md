# Design Review 004: R0099 (raft mode)

Inputs: `z-nile/.tracker/rafts/R0099/R0099.md` after unfolding `c0283` (PR #676) and updating `c0282`'s hash to `origin/main`; member documents `c0263`, `c0280`, `c0284`, `c0282`; prior reviews `design-review-001.md`–`003.md`.
Grouped: [c0263@1b93fc9d0c76, c0280@9db248601f55, c0282@1d0eb2df62b6, c0284@27c0dce08c9e]

## Coherence check
- **Dependency order**: `c0263` (`depends_on: []`) → `c0280` (`[c0263]`) → `c0284` (`[c0263, c0280]`) → `c0282` (`[c0263]`). Neither `c0284` nor `c0282` depends on unfolded `c0283`.
- **Cross-raft waits**: `R0096` is now in `done/`, so `c0282` has no open cross-raft wait.
- **Unfolding `c0283`**: `c0283` is cleanly returned to backlog for re-prep on top of landed `c0369`, unblocking `R0099` and downstream `R0061`.

## Findings

None.

Verdict: approve
