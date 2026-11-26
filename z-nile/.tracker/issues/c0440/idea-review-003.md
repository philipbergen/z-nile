# Idea review 003

## Findings

- F1: Solution sentences 1 and 4 give different answers for any operator other than ";", newline and "&&", so a reader can't tell whether the hook refuses these two lines. First, `cd x && make | tail -5` has no semicolon or newline, so sentence 1 allows it. Sentence 4 refuses it, because `tail` is joined by a pipe, not "&&". Second, `cd x && make || ./zn gate` passes sentence 1 too. Yet when `cd x` fails, `./zn gate` runs in the original folder, which is exactly the problem the idea describes. Sentence 4 refuses it, but only by implication. The solution needs to name every operator a cd may not be followed by (";", newline and "||"). It also needs to say whether a pipe inside one "&&" step is allowed. A pipe there is safe, because the whole pipeline is skipped when the cd fails.

## Verdict

revise
