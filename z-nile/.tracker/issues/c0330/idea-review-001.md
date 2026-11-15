# Idea review 001

## Findings

- F1: Solution sentence 2 ("Such a ticket's claims come from its captured Problem's outcomes alone") would be false as written. `trace.deriveClaims` (`z-nile/engine/trace.luau:367-433`) makes P, S and AC claims, and an empty Solution only removes the S claims. Acceptance criteria stay claims. Read literally, "alone" means dropping AC claims too, which isn't what the idea intends. Say instead that it gets no S claims and keeps its P and AC claims.
- F2: Solution sentence 5 promises an outcome this change can't guarantee. Whether an already-readied raft "passes the trace check" after rebuilding also depends on its own P and AC coverage in the rebuilt `trace.md`. That makes the sentence conditional on work outside this change, and it overlaps Non-goal 4. Limit it to what this change controls: the rebuilt skeleton has no S rows and no Solution refusal for such a ticket.

## Verdict

revise
