# Idea review 001

## Findings

- F1: The Solution's "the raft planner returns the same dependency order as today for every input" cannot be true. Today's `depsFirst` loop (`z-nile/engine/raftplan.luau:104`, `while #out < #issues do`) never ends when two issues share an id. It places the first one, which sets `placed[id]`. It then skips the second on every pass, and the ring fallback skips it too, so `#out < #issues` stays true forever. A bounded loop has to end on that input, so it cannot match today there. The sentence needs to say what the planner returns when ids repeat, or limit "every input" to lists of distinct ids. Rings are not the problem: the fallback that takes the lowest id left already handles them, and a bounded loop can keep that order.

## Verdict

revise
