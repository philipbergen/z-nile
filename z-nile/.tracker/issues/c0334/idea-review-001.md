# Idea review 001

## Findings

- F1: The second non-goal is not a clear fence because "real change" is never defined. Any fix has to change what one of the two commands reports when an empty file is added to or removed from a member after grouping. z-raft records the grouping with `originFolderFiles` and `./zn ready` reads with `treeFolderFiles`, and both keep empty files. `./zn work next` reads with `workread`'s `filesUnder`, which drops them (`z-nile/engine/workread.luau:366`). So `./zn ready` reports adding an empty `acceptance/.gitkeep` as a change today, and `./zn work next` does not. Since the first Solution sentence requires both commands to agree with the record z-raft stored, `./zn work next` will start reporting that edit. Whether that crosses the fence depends on whether adding an empty file is a "real change", and the idea doesn't say.

## Verdict

revise
