# Idea review 003

## Findings

- F1: The third Solution sentence says a round is settled "exactly as f0421 defines it" and then adds a condition f0421 does not have. It says each serious finding at the round maximum must be "recorded as a guess". f0421's rule is `rounds.next` over `rounds.latest(files, "code", doc, isBacklog)` at `rounds.max(limits, "code", level)`, in `z-nile/engine/rounds.luau:196-238`. At the maximum it settles a round once `openlist.unanswered` finds nothing open. In that rule only refuted or still-open findings must be ruled or recorded as a guess. A serious finding marked fixed needs no guess, and `atMaximum` is only a count that `work next` reports. Take a final round `review-005.md` on a normal raft whose one high finding is answered "fixed". f0421 calls it settled, but the sentence as written says `done` must refuse it. A reader cannot tell which one `done` does, so the sentence can't be judged true or false. Say instead that `done` accepts exactly when `rounds.next` returns `settled` (which reuses the existing function), or say that the guess check is a deliberate addition to f0421.

## Verdict

revise
