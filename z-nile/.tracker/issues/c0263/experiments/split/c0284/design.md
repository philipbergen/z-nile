# c0263 hand-off to c0284: the board shows provenance, with c0280's shared reader

Specs here: who.spec.luau (the last case, "the board model carries the same entries as who", is c0284's; the rest is c0280's). Depends on c0263 and c0280 (the shared reader).

Everything below is the c0263 prep text (design-review rounds 003-007), moved here when the user split the issue ("Split it and prototype first, like c0265"). It was NOT prototyped except where it says so; the core layer (c0263: provenance.md, ./zn record, the append-only publish rule, audit, the union of two writers) is prototyped on branch proto-c0263-raft, and this issue prototypes on top of it. Spec files beside this one are the sequestered specs of that prep: they were written against the unprototyped design, so run them on your prototype and fix the ones that cannot pass for a correct implementation.

## Behaviour 8 (the board)

8. **The board shows them (AC9).** `board.build` reads history once per build: one `git log` in trail's format over every root, parsed once by a single `trail.parse` call given every item folder as `dirs` (O(lines), not O(items x lines): E9 measured the per-item version at 5 s for 336 items), the commits bucketed by item, then `trail.life` per item; a tree without git or history builds with the stored rows only, as `history`'s "history unavailable" does) and passes the result into `board.collect` as an optional argument after R0083's `facts`; `collect` puts `provenance: { Entry }` on each `Issue`/`Raft` model: the same entries `who` prints for the same item (the same cut by `trail.cuts`, the same `people`, the same selector), except the derived `rafted` fallback, which needs one `git show` per commit and is printed by `who` only (AC9 pins both); and the item view's script writes a "Provenance" section from it. R0083 (c0118, active: `collect`/`build` take `facts`) and c0265 (work heartbeat, still being designed: its `buildBoard` will compose `collect`/`withVerdicts`/`render`) both change this file; the later to land merges the other's `board.luau` change.

## E9 (the history read once per build: 5.2 s per-item vs O(lines))

- **E9** (run) How long does the board's history read take? Method: a probe calling `trail.parse` once per item folder (336 items) on the 19,823-line log (review 004 F9): 5.2 s; once with every folder in `dirs`: the parse is O(lines) (0.13 s for the `git log`, the parse in the same order). Design: the single call of Behaviour 8; fallback if the board is still slow: the board shows the stored rows only and `who` derives on demand.

## Rules and mutants row (board)

| the board carries the same entries as `who` and writes a Provenance section | who :: the board | the page drops the field | reasoned |

## Acceptance AC9

- AC9: the board model carries each item's `provenance` and the entries equal `who`'s for four kinds of item (a plain life, a reused number, an idea from a first add with a stored and a derived give-back, an old item with no record), except for the one entry that needs a read per commit, the derived `rafted` fallback, which only `who` prints; the item view's script writes a "Provenance" section from it.

## Implementation step 6

6. `board.luau`: the history read once in `build`, passed into `collect` after R0083's `facts`, the `provenance` field and the view section (AC9); merge c0265's and R0083's `board.luau` change if they landed first.
