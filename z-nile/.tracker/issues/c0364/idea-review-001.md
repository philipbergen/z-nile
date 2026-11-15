# Idea review 001

## Findings

- F1: The Problem is narrower than the Solution. The Problem names only c0264's specs, but the Solution covers every promoted spec that reads the z-nile README as text, and that is ten folders. Besides c0264, the promoted specs of c0115, c0116, c0117, c0118, c0183, c0184, c0185, c0246 and c0259 all read `z-nile/README.md` as text, and none of their `watch.txt` files lists it (none of c0264's does either). So the Solution fixes nine folders the Problem never mentions. The Problem should state the wider gap, which c0364's body already asks to check. The Solution should not shrink, because that would cut captured scope. Both Non-goals are real fences. The fix is a list of watch entries, so the selector's dependency logic doesn't change. The duplicated Roadmap rows are not on main and belong to c0365.

## Verdict

revise
