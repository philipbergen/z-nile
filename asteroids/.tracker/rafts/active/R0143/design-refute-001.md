# Refute 001: R0143 (design mode)

- F1: fixed: replaced the paraphrased Theme decisions in `R0143.md` with the verbatim quoted decision lines from `f0220.md` and `f0221.md`; consequences: none (member designs unchanged, `prompt.md` now carries every constraint verbatim).
- F2: fixed: copied the public types and function signatures on shared `Pilot` and `Classic` verbatim from `f0220.md` and `f0221.md` into `R0143.md`'s Whole-raft design, corrected the structural subtyping note (`Classic.Game` satisfies `Classic.Run` and `Classic.Player`), and noted `asteroids/.tracker/architecture.md`'s 7 features and 13 acyclic `deps` edges; consequences: none (member designs unchanged).
