# Idea review 003

## Findings

- F1: Solution sentences 1 and 2 contradict each other for command output. Sentence 1 puts "the commands' output" in scope and allows no word other than the six stage words. Sentence 2 makes an exception for literal paths and stored `status:` values, but only in "the skills and the README". Commands also print such paths. For example, `./zn prompt <R-id> --path` (z-nile/engine/main.luau:134) prints `…/rafts/active/<R-id>/prompt.md`. So either that output breaks sentence 1, or the folders have to be renamed, which the first non-goal forbids. A reader can't tell whether a command that prints a path under `active/` or `done/` passes or fails.

## Verdict

revise
