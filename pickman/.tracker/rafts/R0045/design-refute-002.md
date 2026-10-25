# Response to design-review-002

- Round 1 rulings: accepted.
- F1: fixed: Implementation step 1 now checks the two pre-image blobs (`aa100297`, `21647d7e`) and that the patch applies cleanly, and otherwise stops and escalates for a re-prep, since AC4 cannot pass without editing the sequestered digest; the Design says once that the digests are tied to those blobs. Consequences: none in the specs; both blobs are today's `origin/main`.
- F2: fixed: R0045's Exit criteria say AC1–AC4; c0128's Maintainability names `golden.spec` and how a deliberate edit updates it; Usability says a digest failure prints only two digests and where to look instead; `golden.spec`'s header (comment only) says how to record a new digest and how to find what changed. Consequences: none.
