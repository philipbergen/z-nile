# Answers to design-review-002 (c0264)
Both findings are fixed; none is refuted.

- F1: fixed: AC9 now requires the edges, not only the words. It checks `stack --> loop`, `loop --> layer`, `layer -->|"raft merged: clear context"| loop` and `esc -->|"raft released: clear context"| loop`, and the Design fixes the node ids `stack`, `loop`, `layer` and `esc`. The reviewer's probe (both end edges deleted, their words kept in a floating node) is now the mutant `ends-float`: killed, AC9 (run). Consequences: the Design names the fixed ids; the Rules and mutants row, AC9's text and E4 are updated. An executor who renames a node must keep these ids, which the Design states.
- F2: fixed: the mutant that writes a skeleton diagram is now named `skeleton-diagram`, and a new mutant `todays-diagram` pastes `main`'s own workflow diagram into the draft: killed, AC9 (run). E4 and the Rules and mutants row name both.
