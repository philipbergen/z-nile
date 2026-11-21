# Idea review 002

## Findings

- F1: The first Problem sentence reads as if `main.luau` is over the limit: 203 lines that start with `local`, against a limit of 200. But the file loads and runs. The repo's own lesson (`z-nile/skills/zz-arch/lessons/main-luau-local-limit.md:15`) explains why: the limit counts Luau's local registers, constant locals fold away, and some lines declare two names, so counting `^local` lines does not measure it. A reader who checks will find both numbers true and the conclusion they suggest false. The sentence should state the fact that can be tested: one more non-constant top-level local makes `lune run` fail with "Out of local registers", and `./zn --help` then fails to start. It should not compare a line count to the register limit. The other numbers check out: 9,195 lines, 19 `require` calls inside functions, and 80 `local` lines in `dispatcher.luau`, the next largest file.

## Verdict

revise
