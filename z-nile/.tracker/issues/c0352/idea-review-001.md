# Idea review 001

## Findings

- F1: The first Problem sentence and the first Solution sentence are wrong about the jail marker. `z-nile/tests/lib/fence.luau:929` already passes it to the child explicitly (`export … PICKMAN_TEST_JAIL="$2"`, where `$2` is `jailed`), so spec processes see it in every mode, including inside another sandbox. The comment above the assignment at `fence.luau:922` says it is there for the runner's own lock code (`fence.alive`), not for children. Only `PICKMAN_WORKER_LANES` (`fence.luau:896`) is set by assignment alone and is missing from that export. `tests/run.luau:368` reads it in the inner runner, finds nothing, and starts workers without the lane wrapper. The jail-marker half describes a defect that doesn't exist and asks for a fix that is already in place.
- F2: The third Solution sentence ("No value in z-nile that is meant for a child process…") goes beyond the problem, which names one value. It also can't be found true or false: "meant for a child process" is a judgment call, not something you can check. Assignments like `work.spec.luau:274` (`HOME`, read in-process) show the line is unclear. Either name the values it covers or make it a checkable rule.

## Verdict

revise
