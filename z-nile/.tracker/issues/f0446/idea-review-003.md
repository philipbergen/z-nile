# Idea review 003

## Findings

- F1: "work profile" in the slicing sentence names nothing that exists. It appears nowhere in `z-nile/` or the trackers, while every other slice does (the model aliases are in `z-nile/engine/models.luau`, tributaries in `z-nile/engine/tributaries.luau`). So a reader can't tell whether "every base measure can be sliced by … work profile" is true or false: it could mean an alias configuration, a `.models.toml` level or something not yet built. Either define it in one clause, name the ticket that brings it in, or drop it from the slice list.

## Verdict

revise
