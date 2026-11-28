# Idea review 003

## Findings

- F1: Solution bullet 3 states a false fact about today, and it hides scope. It says `./zn work` and `./zn dispatch` pass `--on` themselves "just as they do today for a raft with an unlanded dependency". Today `./zn dispatch` never does: its ready step runs `ready {id}` with no `--on` (`z-nile/engine/dispatch.luau:29`), and `ready` refuses the flag under `ZN_DISPATCH` with "--on is not for ./zn dispatch" (`z-nile/engine/main.luau:6884`). `./zn work next` only prints the `./zn ready <R-id> --on <base>` line for the worker to run (`z-nile/engine/work.luau:1366` and `:1900`). Bullet 2 removes only the light-path refusal at `main.luau:6911`, so the refusal at `:6884` still blocks bullet 3 for dispatch. The idea must either limit bullet 3 to what `./zn work` names, or state stacking under dispatch as new behaviour, with that second refusal removed and a Problem sentence behind it.

## Verdict

revise
