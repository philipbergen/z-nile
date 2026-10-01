# Refute 003: R0160

- F1: deferred c0530: the claims in c0460.md are corrected in this PR (Design, E5, the Rules and mutants rows and AC3 prose now say exactly what the spec checks, and list the five surviving mutants as a known gap), which is a documentation fix. The stronger fix, running the whole of `setup.sh` against stub tools, is a new design with an experiment (how much of the script can be stubbed without editing it), and the remaining fixes would change a sequestered spec after the last review round, so a new reviewer could not verify them: filed as c0530 (backlog chore). The CI gate itself is unchanged and correct: `scripts/setup.sh` equals main's.
- F2: deferred c0530: the spec leaves temp directories behind on every run; folded into c0530.
- F3: deferred c0530: a correct `setup.sh` fails the spec if a comment or message contains the word "exit", and the spec's error line numbers are off; folded into c0530.
