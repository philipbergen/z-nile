# Idea review 001

## Findings

- F1: "Open finding" has no definition, and so Solution sentences 2 and 4 contradict sentence 3. Under f0421's round rules, a latest code review settles while findings are still open: low findings settle once answered, and serious findings settle at the round maximum once answered and recorded as a guess. Sentence 3 accepts such a layer, while sentences 2 and 4 refuse it, so a reader can't tell whether `./zn done` refuses or accepts it. The fix is to say which f0421 state the check requires, for example "the latest round is settled: approve, or answered as `openlist.unanswered` defines it". Then the three sentences agree and each can be tested. (Problem sentence 1 checks out: f0421's E2 records that `done` reads only `final-review-NNN.md` and never asks for a `review-NNN.md`.)

## Verdict

revise
