# Final refute 002

- F1: fixed ecace01c1: the CPU-refusal case in `tests/tooling/watch-net-bounded.spec.luau` builds a stale history and expects the no-pass line on the refused kick's stdout; with the call dropped from that path the case fails (2 passed, 1 failed); the failed-start path (`started.ok` false: the detaching `perl` could not be run) still has no case of its own, because no fixture can make that call fail without replacing `perl`; it is the same one-line call as the other two; consequences: the bounded spec builds two more commits in one fixture, a second or two.
