# Idea review 001

## Findings

- F1: The Solution's middle clause names a proof the spec doesn't make. The only `env -i` text in the promoted spec is at `z-nile/tests/acceptance/c0371/check-paths-homes.spec.luau:694`. It sits in the case "grep's pattern is text as main reads it". It asserts that `env -i grep -qF "src/nothing" "$F"` gives no findings, so grep's pattern stays text after `env -i`. The wording "an `env -i` introducer leaves a helper's arguments read as paths" comes from c0371's design, where it is listed as an accepted limitation (`done/c0371/c0371.md:76`). No case in the spec asserts it. A reader checking the sentence against the spec would find it false. An implementer told to "still prove" it must either keep a proof that isn't there or add a new case, and that grows the fix beyond the smallest one. The clause should name what line 694 actually proves: an unquoted `grep` after `env -i` still has its pattern read as text.

## Verdict

revise
