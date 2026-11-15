# Idea review 001

## Findings

- F1: For wrapper-guards, the Problem sentence is false and the Solution sentence is unsafe. That spec runs the dispatch wrapper on purpose: `{TOP}/z-nile/bin/git` is the thing it tests. What breaks under dispatch is how it finds the real git to put behind the wrapper. `realGit` comes from `command -v git` (`z-nile/tests/tooling/wrapper-guards.spec.luau:54`) and is passed as `ZN_REAL_GIT`. Under dispatch that lookup finds the wrapper, so the wrapper ends up wrapping itself. Read literally, "the fixtures invoke the real git regardless of what PATH offers" would stop those specs from running the wrapper at all, and they would pass without testing what they exist to test. The idea should say the fix is in where the real git comes from: the git the fixtures hand the wrapper as `ZN_REAL_GIT`, and the git they call directly, are found without the dispatch wrapper. The wrapper stays the thing under test. (I checked the other risk too: the runner's repo fence works through environment variables, not a git on PATH, so skipping PATH does not get around it.)

## Verdict

revise
