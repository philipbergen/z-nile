# Refutations and fixes: design-review-023
- F1: fixed: a case makes `gh` fail while every claim is fresh and expects a clean answer (mutant K7); stated in Delivery.
- F2: fixed: a git stand-in answers the first branch lookup of a drawn claim stamp as taken, and the claim must look up twice (mutant K8); the row is `run`.
- F3: fixed: a takeover during the beat's branch read must not get the taker's branch pruned (edge; mutant K9).
- F4: fixed: parse shape and state cases (K11, K13), `lost` exits 0 with a malformed branch (K12), the lock retry on the fetch of main (K10), `nolog` narrowed to the since read.
- F5: fixed: the hang markers are 120 s with 60 s limits, `wtB` is declared; AC4's hash updated; race.spec rerun on the prototype and on the envelope with variants A and B.
- F6: fixed: nobeat wording (stale and never beaten), variants A and B as hashed patches, the main-checkout constraint.
